import Foundation

enum ProviderReplyChecks {
    static let valid = #"{"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"  Exact synthetic text.  ","refusal":null}}]}"#
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        let completed = try ProviderReplyTransport.text(in: Data(valid.utf8))
        check(completed == "Exact synthetic text.", "completed assistant text keeps its literal content and trims only outer whitespace")
        let bad = [
            ("token limit", valid.replacingOccurrences(of: "\"stop\"", with: "\"length\"")),
            ("content filter", valid.replacingOccurrences(of: "\"stop\"", with: "\"content_filter\"")),
            ("tool finish", valid.replacingOccurrences(of: "\"stop\"", with: "\"tool_calls\"")),
            ("function finish", valid.replacingOccurrences(of: "\"stop\"", with: "\"function_call\"")),
            ("missing finish", valid.replacingOccurrences(of: "\"finish_reason\":\"stop\",", with: "")),
            ("null finish", valid.replacingOccurrences(of: "\"stop\"", with: "null")),
            ("refusal beside text", valid.replacingOccurrences(of: "\"refusal\":null", with: "\"refusal\":\"declined\"")),
            ("malformed refusal", valid.replacingOccurrences(of: "\"refusal\":null", with: "\"refusal\":false")),
            ("nonassistant role", valid.replacingOccurrences(of: "\"assistant\"", with: "\"user\"")),
            ("wrong index", valid.replacingOccurrences(of: "\"index\":0", with: "\"index\":1")),
            ("missing index", valid.replacingOccurrences(of: "\"index\":0,", with: "")),
            ("duplicate finish", valid.replacingOccurrences(of: "\"finish_reason\":\"stop\"", with: "\"finish_reason\":\"length\",\"finish_reason\":\"stop\"")),
            ("tool payload despite stop", valid.replacingOccurrences(of: "\"refusal\":null", with: "\"tool_calls\":[{\"id\":\"synthetic\"}]")),
            ("function payload despite stop", valid.replacingOccurrences(of: "\"refusal\":null", with: "\"function_call\":{\"name\":\"synthetic\"}")),
            ("missing content", valid.replacingOccurrences(of: "\"content\":\"  Exact synthetic text.  \",", with: "")),
            ("blank content", valid.replacingOccurrences(of: "Exact synthetic text.", with: "")),
            ("top-level error", valid.replacingOccurrences(of: "{\"choices\"", with: "{\"error\":{},\"choices\"")),
            ("multiple choices", #"{"choices":[{"index":0},{"index":1}]}"#),
            ("non-JSON stream", "data: " + valid + "\n\ndata: [DONE]"),
            ("truncated JSON", String(valid.dropLast())),
            ("trailing non-JSON", valid + "unexpected")
        ]
        for (name, text) in bad {
            let rejected: Bool
            do { _ = try ProviderReplyTransport.text(in: Data(text.utf8)); rejected = false } catch { rejected = true }
            check(rejected, "provider parser rejects " + name + " without returning partial prose")
        }
        check((try? ProviderReplyTransport.text(in: Data([0xFF]))) == nil, "provider parser refuses invalid UTF8 instead of replacing source characters")
        let absentRefusal = valid.replacingOccurrences(of: ",\"refusal\":null", with: "")
        check((try? ProviderReplyTransport.text(in: Data(absentRefusal.utf8))) != nil, "compatible complete reply may omit the optional refusal field")
        let emptyTools = valid.replacingOccurrences(of: "\"refusal\":null", with: "\"refusal\":\"\",\"tool_calls\":[],\"function_call\":null")
        check((try? ProviderReplyTransport.text(in: Data(emptyTools.utf8))) != nil, "explicit empty optional refusal and tool fields do not invent a tool request")
        let boundary = Data((valid + String(repeating: " ", count: ProviderReplyTransport.maxResponseBytes - valid.utf8.count)).utf8)
        check((try? ProviderReplyTransport.text(in: boundary)) == "Exact synthetic text.", "complete provider envelope at the exact decoded-body limit is accepted")
        check((try? ProviderReplyTransport.text(in: boundary + Data([32]))) == nil, "one byte above the decoded provider-body limit is rejected")
    }

    /// Explicit loopback-only integration probe; ordinary logic checks never
    /// make network requests. The server and every payload are synthetic.
    static func transport(endpoint: URL, output: URL) async throws {
        precondition(endpoint.scheme == "http" && endpoint.host == "127.0.0.1")
        var outcomes: [[String: Any]] = []
        func report(_ status: String) throws {
            try JSONSerialization.data(withJSONObject: ["status":status,"cases":outcomes,"scope":"Actual URLSession loopback transport with synthetic bodies only; no credential, live provider or clinical claim."], options: [.prettyPrinted,.sortedKeys]).write(to: output)
        }
        func request(_ route: String, timeout: Double = 60) -> URLRequest {
            var request = URLRequest(url: endpoint.appendingPathComponent(route), timeoutInterval: timeout)
            request.httpMethod = "POST"; request.httpBody = Data("{\"synthetic\":true}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return request
        }
        do {
            for route in ["stop", "utf8-chunks", "exact-limit"] {
                let actual = try await ProviderReplyTransport.send(request(route))
                let expected = route == "utf8-chunks" ? "Café 🧑🏽‍⚕️ · 12,5 µg/L" : "Exact synthetic text."
                guard actual == expected else { throw ProbeFailure.failed(route) }
                outcomes.append(["route":route,"status":"passed","result":"exact text preserved"])
            }
            for (route, expected) in [("length",ProviderReplyTransport.Failure.incomplete),("refusal",.refusal),("filter",.incomplete),("tool",.incomplete),("http-error",.http),("redirect",.http),("nonjson",.malformed),("oversize-header",.responseSize),("oversize-chunked",.responseSize)] {
                do { _ = try await ProviderReplyTransport.send(request(route)); throw ProbeFailure.failed(route) }
                catch let failure as ProviderReplyTransport.Failure {
                    guard failure == expected else { throw ProbeFailure.failed(route) }
                    outcomes.append(["route":route,"status":"passed","result":String(describing:failure)])
                }
            }
            var oversized = request("request-must-not-arrive")
            oversized.httpBody = Data(repeating: 32, count: ProviderReplyTransport.maxRequestBytes + 1)
            do { _ = try await ProviderReplyTransport.send(oversized); throw ProbeFailure.failed("request limit") }
            catch ProviderReplyTransport.Failure.requestSize { outcomes.append(["route":"request-must-not-arrive","status":"passed","result":"rejected before networking"] ) }
            let clock = ContinuousClock(), start = clock.now
            let pending = Task { try await ProviderReplyTransport.send(request("slow")) }
            try await Task.sleep(nanoseconds: 200_000_000); pending.cancel()
            do { _ = try await pending.value; throw ProbeFailure.failed("cancel") }
            catch is CancellationError { }
            catch let error as URLError where error.code == .cancelled { }
            let cancellationSeconds = Double(start.duration(to: clock.now).components.attoseconds) / 1e18 + Double(start.duration(to: clock.now).components.seconds)
            guard cancellationSeconds < 3 else { throw ProbeFailure.failed("cancel latency") }
            outcomes.append(["route":"slow","status":"passed","result":"cancelled without partial reply","seconds":cancellationSeconds])
            do { _ = try await ProviderReplyTransport.send(request("slow", timeout: 0.2)); throw ProbeFailure.failed("timeout") }
            catch let error as URLError where error.code == .timedOut { outcomes.append(["route":"slow-timeout","status":"passed","result":"idle timeout without partial reply"]) }
            try report("passed")
        } catch {
            outcomes.append(["status":"failed","error":String(describing:error)]); try report("failed"); throw error
        }
    }
    enum ProbeFailure: Error { case failed(String) }
}
