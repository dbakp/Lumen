// App Designer Pro device chrome: injects the status bar, the Dynamic Island
// or camera hole, and the home indicator or gesture handle into every
// .screen. iPhone by default; data-os="android" for a Pixel-class phone.
// Loads the Android faces and Material Symbols when the page uses them.
// See device.css for every option.
(() => {
  const ios = {
    signal: `<svg width="19" height="12" viewBox="0 0 19 12"><rect x="0" y="7.5" width="3.2" height="4.5" rx="1"/><rect x="5" y="5" width="3.2" height="7" rx="1"/><rect x="10" y="2.5" width="3.2" height="9.5" rx="1"/><rect x="15" y="0" width="3.2" height="12" rx="1"/></svg>`,
    wifi: `<svg width="17" height="12" viewBox="0 0 17 12"><path d="M8.5 2.6c2.3 0 4.4.9 6 2.4l1.2-1.2A10.2 10.2 0 0 0 8.5.9 10.2 10.2 0 0 0 1.3 3.8L2.5 5a8.5 8.5 0 0 1 6-2.4Zm0 3.4c1.4 0 2.6.5 3.6 1.4l1.2-1.2A6.8 6.8 0 0 0 8.5 4.3c-1.8 0-3.5.7-4.8 1.9l1.2 1.2c1-.9 2.2-1.4 3.6-1.4Zm0 3.4c-.5 0-1 .2-1.3.5L8.5 11.2l1.3-1.3c-.3-.3-.8-.5-1.3-.5Z"/></svg>`,
    battery: `<svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.8" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.5"/><path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2Z" opacity=".45"/></svg>`,
  };
  // Pixel status icons: the filled Wi-Fi fan, the cellular wedge, and the
  // horizontal battery of Android 16.
  const android = {
    wifi: `<svg width="17" height="13" viewBox="0 0 17 13"><path d="M8.5 12.6.4 3.9a11.6 11.6 0 0 1 16.2 0Z"/></svg>`,
    signal: `<svg width="14" height="14" viewBox="0 0 14 14"><path d="M13.6.4v13.2H.4Z"/></svg>`,
    battery: `<svg width="25" height="13" viewBox="0 0 25 13"><rect x=".7" y=".7" width="21.4" height="11.6" rx="4" fill="none" stroke="currentColor" stroke-width="1.4" opacity=".45"/><rect x="2.6" y="2.6" width="15.6" height="7.8" rx="2.2"/><rect x="23" y="4.4" width="1.6" height="4.2" rx=".8" opacity=".45"/></svg>`,
  };

  // Clones first: <section class="screen" data-clone="today"> becomes a
  // copy of the screen named "today" (markup and attributes), so a store
  // panel or a stage always shows the current design.
  // The source is the top-level screen of that name (never another copy in
  // a device), and the copy takes its classes and attributes too, because a
  // design's CSS is often keyed on them.
  for (const c of document.querySelectorAll("[data-clone]")) {
    const named = [...document.querySelectorAll(".screen[data-name]")].filter((x) => x !== c && x.dataset.name === c.dataset.clone);
    const src = named.find((x) => !x.closest(".device, .panel, .stage") && !x.hasAttribute("data-clone")) || named.find((x) => !x.closest(".device, .panel, .stage") && x.children.length);
    if (!src) { c.innerHTML = `<p style="padding:80px 24px;font:600 15px system-ui;color:#c00">No screen named "${c.dataset.clone}" to clone.</p>`; continue; }
    for (const cls of src.classList) c.classList.add(cls);
    for (const { name, value } of src.attributes) if (!["class", "data-pair", "data-motion", "data-kind", "data-clone", "id"].includes(name) && !c.hasAttribute(name)) c.setAttribute(name, value);
    c.innerHTML = src.innerHTML;
  }

  // A dark ground without data-chrome or data-theme gets light chrome.
  const lum = (c) => {
    const m = c.match(/rgba?\(([^)]+)\)/); if (!m) return null;
    const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number);
    if ((p[3] ?? 1) < 0.5) return null;
    const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
    return 0.2126 * f(p[0]) + 0.7152 * f(p[1]) + 0.0722 * f(p[2]);
  };

  const screens = document.querySelectorAll(".screen, .mini-screen");
  let needsAndroid = false;
  for (const s of screens) {
    const isAndroid = s.dataset.os === "android";
    if (isAndroid) needsAndroid = true;
    if (s.dataset.chrome === "none") continue;
    if (!s.dataset.chrome && !s.dataset.theme) {
      const L = lum(getComputedStyle(s).backgroundColor);
      if (L !== null && L < 0.18) s.dataset.chrome = "light";
    }
    const time = s.dataset.time || "9:41";
    if (isAndroid) {
      s.insertAdjacentHTML(
        "beforeend",
        `<div class="ac-status" aria-hidden="true"><span>${time}</span><span class="ac-right">${android.wifi}${android.signal}${android.battery}</span></div>` +
          `<div class="ac-camera" aria-hidden="true"></div>` +
          `<div class="ac-home" aria-hidden="true"></div>`
      );
    } else {
      s.insertAdjacentHTML(
        "beforeend",
        `<div class="ac-status" aria-hidden="true"><span>${time}</span><span class="ac-right">${ios.signal}${ios.wifi}${ios.battery}</span></div>` +
          `<div class="ac-island" aria-hidden="true"></div>` +
          `<div class="ac-home" aria-hidden="true"></div>`
      );
    }
  }

  // Fonts from Google Fonts, only when the page needs them, so an iPhone-only
  // mockup still renders offline. display=block: a mockup is never shot in
  // a fallback face.
  const links = [];
  const usesGoogleFaces = () => {
    for (const el of document.body.querySelectorAll("*")) if (/Google Sans|Roboto Flex/.test(getComputedStyle(el).fontFamily)) return true;
    return false;
  };
  if (needsAndroid || document.querySelector(".adaptive-icon, .panel[data-store='play'], .panel[data-store='feature']") || usesGoogleFaces())
    links.push(
      "https://fonts.googleapis.com/css2?family=Google+Sans+Flex:opsz,wdth,wght,GRAD,ROND@6..144,25..151,1..1000,0..100,0..100&family=Roboto+Flex:opsz,wdth,wght,GRAD@8..144,25..151,100..1000,-200..150&display=block"
    );
  const symbols = new Set();
  for (const el of document.querySelectorAll(".ms")) {
    symbols.add(el.classList.contains("ms-outlined") ? "Outlined" : el.classList.contains("ms-sharp") ? "Sharp" : "Rounded");
  }
  for (const style of symbols)
    links.push(`https://fonts.googleapis.com/css2?family=Material+Symbols+${style}:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=block`);
  for (const href of links) {
    if (document.querySelector(`link[href="${href}"]`)) continue;
    const l = document.createElement("link");
    l.rel = "stylesheet";
    l.href = href;
    document.head.appendChild(l);
  }
})();
