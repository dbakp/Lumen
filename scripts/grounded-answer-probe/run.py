"""One frozen generative policy; raw outputs persist before quality evaluation."""
import argparse
import gc
import json
import math
import os
from pathlib import Path
import platform
import time

import numpy as np
import torch
import transformers
from transformers import AutoModelForCausalLM, AutoTokenizer, GenerationConfig, LogitsProcessor

from common import EVIDENCE, PROTOCOL_SHA, checked, file_digest, policy, save, sha


class FiniteLogits(LogitsProcessor):
    def __init__(self):
        self.checks = 0

    def __call__(self, input_ids, scores):
        if not torch.isfinite(scores).all().item():
            raise ValueError("nonfiniteGenerationLogits")
        self.checks += 1
        return scores


def load(directory, dtype, device):
    model, info = AutoModelForCausalLM.from_pretrained(directory, local_files_only=True, trust_remote_code=False,
        use_safetensors=True, torch_dtype=dtype, attn_implementation="eager", output_loading_info=True,
        low_cpu_mem_usage=False)
    if any(info.get(key) for key in ("missing_keys", "unexpected_keys", "mismatched_keys", "error_msgs")):
        raise ValueError("Incomplete/mismatched model initialization: " + str(info))
    return model.eval().to(device), info


def numerical_inputs(tokenizer, frozen):
    return [tokenizer.apply_chat_template([{"role": "user", "content": text}], tokenize=True,
            add_generation_prompt=True, enable_thinking=False, return_tensors="pt")
            for text in frozen["runtime"]["numericalControls"]["inputs"]]


def last_logits(model, ids):
    with torch.inference_mode():
        output = model(input_ids=ids.to(model.device), attention_mask=torch.ones_like(ids).to(model.device), use_cache=False)
    result = output.logits[0, -1].float().cpu().numpy().copy()
    if not np.isfinite(result).all():
        raise ValueError("nonfiniteNumericalProbe")
    return result


def run(work, resume=False):
    frozen = policy()
    producer_paths = [Path(__file__), Path(__file__).with_name("common.py")]
    producer = {p.name: file_digest(p) for p in producer_paths}
    model_receipt = json.loads((work / "model/receipt.json").read_bytes())
    if model_receipt["revision"] != frozen["model"]["revision"] or model_receipt["protocolSHA256"] != PROTOCOL_SHA:
        raise ValueError("Changed model receipt")
    expected = {row["rfilename"]: row for row in frozen["model"]["selectedFiles"]}
    if {row["file"] for row in model_receipt["files"]} != set(expected):
        raise ValueError("Incomplete pinned model files")
    for row in model_receipt["files"]:
        path = work / "model" / row["file"]
        if path.is_symlink() or path.stat().st_size != expected[row["file"]]["size"] or file_digest(path) != row["sha256"]:
            raise ValueError("Changed local model input")
        pin = expected[row["file"]]
        if "lfs" in pin and row["sha256"] != pin["lfs"]["sha256"]:
            raise ValueError("Changed pinned weight/tokenizer object")
    prepared = json.loads((work / "prepared.json").read_bytes())
    if prepared["protocolSHA256"] != PROTOCOL_SHA:
        raise ValueError("Changed input policy")
    examples = [json.loads(line) for line in checked(work / "synthetic-inputs.jsonl", prepared["inputsSHA256"]).splitlines()]
    if len(examples) != 72 or len({row["id"] for row in examples}) != 72:
        raise ValueError("Incomplete quality denominator")
    prompt = checked(EVIDENCE / "prompt.txt", frozen["prompt"]["sha256"]).decode()
    for row in examples:
        if {s["id"] for s in row["sources"]} != set(row["owners"]) or set(row["owners"]) != set(row["sourceBodySHA256"]):
            raise ValueError("Incomplete source map")
        for source in row["sources"]:
            if sha(source["savedText"].encode()) != row["sourceBodySHA256"][source["id"]]:
                raise ValueError("Changed original source text")
    if not torch.backends.mps.is_available():
        raise ValueError("Declared MPS device unavailable")
    torch.set_num_threads(4); torch.set_num_interop_threads(1)
    tokenizer = AutoTokenizer.from_pretrained(work / "model", local_files_only=True, trust_remote_code=False, use_fast=True)
    controls_path = work / "numerical-controls.json"
    if not controls_path.exists():
        print("Loading CPU FP32 numerical reference (three non-quality inputs)", flush=True)
        model, cpu_info = load(work / "model", torch.float32, "cpu")
        probes = numerical_inputs(tokenizer, frozen)
        reference = [last_logits(model, ids) for ids in probes]
        del model; gc.collect()
        print("CPU reference unloaded; loading MPS FP16", flush=True)
    else:
        if not resume:
            raise ValueError("Existing controls/output; explicit resume required")
        reference = None
    model, mps_info = load(work / "model", torch.float16, "mps")
    if reference is not None:
        outcomes = []
        for index, (ids, expected_logits) in enumerate(zip(probes, reference)):
            actual = last_logits(model, ids)
            difference = float(np.max(np.abs(actual - expected_logits)))
            outcomes.append({"inputIndex": index, "maximumAbsoluteLogitDifference": difference,
                             "CPUFP32Top1Token": int(np.argmax(expected_logits)), "MPSFP16Top1Token": int(np.argmax(actual)),
                             "allFinite": True, "passed": difference <= .25 and int(np.argmax(expected_logits)) == int(np.argmax(actual))})
        save(controls_path, {"protocolSHA256": PROTOCOL_SHA, "producerSHA256": producer, "modelReceiptSHA256": file_digest(work / "model/receipt.json"),
            "passed": all(row["passed"] for row in outcomes), "cases": outcomes, "cpuLoadingInfo": cpu_info, "mpsLoadingInfo": mps_info,
            "scope": "Only three non-quality next-token logit probes; no full CPU/FP32/native generation parity claim."})
        del reference, probes; gc.collect()
    controls = json.loads(controls_path.read_bytes())
    if not controls["passed"] or controls["protocolSHA256"] != PROTOCOL_SHA or controls["producerSHA256"] != producer or controls["modelReceiptSHA256"] != file_digest(work / "model/receipt.json"):
        raise ValueError("Numerical controls failed or changed; no quality inference permitted")
    start_proof = {"protocolSHA256": PROTOCOL_SHA, "producerSHA256AtStart": producer, "inputsSHA256": prepared["inputsSHA256"],
        "modelReceiptSHA256": file_digest(work / "model/receipt.json"), "versions": {"torch": torch.__version__, "transformers": transformers.__version__, "python": platform.python_version()},
        "device": "mps", "precision": "FP16", "platform": platform.platform(), "goldLoadedByInference": False}
    start_path = work / "run-start.json"
    output_path = work / "synthetic-outputs.jsonl"
    if start_path.exists():
        if not resume or json.loads(start_path.read_bytes()) != start_proof:
            raise ValueError("Changed resume producer/input/runtime")
    else:
        if resume:
            raise ValueError("No original run to resume")
        save(start_path, start_proof)
    completed = []
    if output_path.exists():
        if not resume:
            raise ValueError("Output exists")
        completed = [json.loads(line) for line in output_path.read_bytes().splitlines()]
        if [row["id"] for row in completed] != [row["id"] for row in examples[:len(completed)]]:
            raise ValueError("Incomplete/changed existing output sequence")
    eos = model.generation_config.eos_token_id
    eos_ids = [eos] if isinstance(eos, int) else eos
    settings = frozen["runtime"]["sampling"]
    configuration = GenerationConfig(**settings, eos_token_id=eos, pad_token_id=tokenizer.pad_token_id,
                                    bos_token_id=tokenizer.bos_token_id)
    with output_path.open("a" if resume else "x") as stream:
        for index, example in enumerate(examples[len(completed):], start=len(completed)):
            payload = json.dumps({"question": example["question"], "sources": example["sources"]}, ensure_ascii=False, separators=(",", ":"))
            messages = [{"role": "system", "content": prompt}, {"role": "user", "content": payload}]
            text = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True, enable_thinking=False)
            inputs = tokenizer(text, return_tensors="pt", add_special_tokens=False)
            count = int(inputs["input_ids"].shape[1])
            seed = int(sha(example["id"].encode())[:8], 16)
            result = {"id": example["id"], "group": example["group"], "seed": seed, "promptTokens": count,
                      "promptSHA256": sha(text.encode()), "inputPayloadSHA256": sha(payload.encode()), "rawText": "", "generatedTokenIDs": [], "generationComplete": False}
            if count > 8192 or count + 512 > model.config.max_position_embeddings:
                result["status"] = "inputLimit"
            else:
                torch.manual_seed(seed); torch.mps.manual_seed(seed)
                guard = FiniteLogits()
                tensors = {key: value.to("mps") for key, value in inputs.items()}
                torch.mps.synchronize(); start = time.perf_counter()
                with torch.inference_mode():
                    output = model.generate(**tensors, generation_config=configuration, logits_processor=[guard])
                torch.mps.synchronize(); elapsed = time.perf_counter() - start
                generated = output[0, count:].cpu().tolist()
                complete = bool(generated and generated[-1] in eos_ids)
                content = generated[:-1] if complete else generated
                result.update({"status": "generated" if complete else "lengthLimit", "rawText": tokenizer.decode(content, skip_special_tokens=False),
                    "generatedTokenIDs": generated, "generationComplete": complete, "generationSeconds": elapsed, "finiteLogitSteps": guard.checks})
                del tensors, output
            stream.write(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n"); stream.flush(); os.fsync(stream.fileno())
            print(index + 1, "/72", example["id"], result["status"], len(result["generatedTokenIDs"]), "tokens", flush=True)
    if producer != {p.name: file_digest(p) for p in producer_paths}:
        raise ValueError("Producer changed during quality inference")
    results = [json.loads(line) for line in output_path.read_bytes().splitlines()]
    if len(results) != len(examples) or [row["id"] for row in results] != [row["id"] for row in examples]:
        raise ValueError("Incomplete output denominator")
    save(work / "run-complete.json", dict(start_proof, outputsSHA256=file_digest(output_path), questions=len(results),
        generatedTokens=sum(len(row["generatedTokenIDs"]) for row in results), generationSeconds=sum(row.get("generationSeconds", 0) for row in results),
        numericalControlsSHA256=file_digest(controls_path), timingScope="Synchronized MPS generation calls including sampling and finite guards; excludes loading/tokenizing/JSON validation. Not native/iPhone latency."))
    del model; gc.collect(); torch.mps.empty_cache()
    print("Completed all72 raw outputs; no gold/quality scoring in runner", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("work", type=Path); parser.add_argument("--resume", action="store_true")
    args = parser.parse_args(); run(args.work, args.resume)
