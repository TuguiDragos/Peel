const reveals = document.querySelectorAll(".reveal");
if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("shown");
        observer.unobserve(entry.target);
      }
    }
  }, { rootMargin: "0px 0px -8% 0px" });
  reveals.forEach((element) => observer.observe(element));
} else {
  reveals.forEach((element) => element.classList.add("shown"));
}

document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.textContent = "Copied";
      button.classList.add("done");
    } catch {
      button.textContent = "Press ⌘C";
      const range = document.createRange();
      range.selectNodeContents(button.previousElementSibling);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
    }
    setTimeout(() => {
      button.textContent = "Copy";
      button.classList.remove("done");
    }, 2000);
  });
});

// Chip rows wrap evenly, like balanced text, never narrower than their widest chip.
const balanceChips = (list) => {
  list.style.maxWidth = "";
  const items = [...list.children];
  const rows = () => new Set(items.map((item) => item.offsetTop)).size;
  const count = rows();
  if (count < 2) return;
  let [low, high] = [Math.max(...items.map((item) => item.offsetWidth)), list.clientWidth];
  while (high - low > 2) {
    const middle = (low + high) / 2;
    list.style.maxWidth = `${middle}px`;
    if (rows() > count) low = middle;
    else high = middle;
  }
  list.style.maxWidth = `${Math.ceil(high)}px`;
};
// Balanced again whenever the room around a list changes width, which a page laid out before it was shown needs too.
const chipLists = new Map(
  [...document.querySelectorAll(".chips, .languages")].map((list) => [list.parentElement, list])
);
chipLists.forEach(balanceChips);
const chipRoom = new Map();
const chipObserver = new ResizeObserver((entries) => {
  for (const { target, contentRect } of entries) {
    if (chipRoom.get(target) === contentRect.width) continue;
    chipRoom.set(target, contentRect.width);
    requestAnimationFrame(() => balanceChips(chipLists.get(target)));
  }
});
chipLists.forEach((list, room) => chipObserver.observe(room));

const toTop = document.querySelector(".to-top");
const heroActions = document.querySelector(".hero .actions");
const ringByScript = !CSS.supports("animation-timeline: scroll()");
let toTopQueued = false;
const updateToTop = () => {
  toTopQueued = false;
  // Shown once the Download button has scrolled away above.
  toTop.classList.toggle("shown", heroActions.getBoundingClientRect().bottom < 0);
  // Where CSS can't follow the scroll, the ring is filled here.
  if (ringByScript) {
    const range = document.documentElement.scrollHeight - innerHeight;
    toTop.style.setProperty("--progress", range > 0 ? Math.min(1, scrollY / range) : 0);
  }
};
const queueToTop = () => {
  if (toTopQueued) return;
  toTopQueued = true;
  requestAnimationFrame(updateToTop);
};
addEventListener("scroll", queueToTop, { passive: true });
addEventListener("resize", queueToTop);
updateToTop();

const themeButtons = document.querySelectorAll("[data-theme]");
const themeName = document.getElementById("theme-name");
let themeShown = document.getElementById("theme-image");
let themeNext = themeShown.cloneNode();
themeNext.removeAttribute("id");
themeNext.removeAttribute("src");
themeNext.removeAttribute("loading");
themeNext.classList.remove("shown");
themeNext.alt = "";
themeNext.setAttribute("aria-hidden", "true");
let themeWanted = "";
const themeURL = (button) => `images/terminal-${button.dataset.theme}-1200.webp`;

// Scrolls the row only, never the page.
const themeList = document.querySelector(".theme-list");
const calm = matchMedia("(prefers-reduced-motion: reduce)");
const centerTheme = (button, behavior) => {
  const item = button.parentElement;
  themeList.scrollTo({ left: item.offsetLeft - (themeList.clientWidth - item.offsetWidth) / 2, behavior });
};
// The theme shown is centered again whenever the row changes width, as when it is first laid out.
let themeRowWidth;
new ResizeObserver(([{ contentRect }]) => {
  if (contentRect.width === themeRowWidth) return;
  themeRowWidth = contentRect.width;
  const shown = document.querySelector('[data-theme][aria-pressed="true"]');
  if (shown) centerTheme(shown, "instant");
}).observe(themeList);

themeButtons.forEach((button) => {
  const warm = () => { new Image().src = themeURL(button); };
  button.addEventListener("pointerenter", warm, { once: true });
  button.addEventListener("focus", warm, { once: true });
  button.addEventListener("click", async () => {
    const name = button.textContent.trim();
    themeButtons.forEach((other) => other.setAttribute("aria-pressed", String(other === button)));
    centerTheme(button, calm.matches ? "instant" : "smooth");
    themeName.textContent = name;
    themeWanted = name;
    if (!themeNext.isConnected) themeShown.after(themeNext);
    themeNext.src = themeURL(button);
    try {
      await themeNext.decode();
    } catch {
      return;
    }
    // Only the last theme asked for is shown.
    if (themeWanted !== name) return;
    themeNext.alt = `The ${name} theme in Terminal`;
    themeNext.removeAttribute("aria-hidden");
    themeShown.alt = "";
    themeShown.setAttribute("aria-hidden", "true");
    themeNext.classList.add("shown");
    themeShown.classList.remove("shown");
    [themeShown, themeNext] = [themeNext, themeShown];
  });
});

// The release GitHub calls the latest, the one the Download link's own address leads to. Without an answer,
// Download keeps pointing at that release's page.
fetch("https://api.github.com/repos/TuguiDragos/Peel/releases/latest", {
  headers: { Accept: "application/vnd.github+json" },
  priority: "low",
})
  .then((response) => (response.ok ? response.json() : Promise.reject(response.status)))
  .then((release) => {
    const prefix = "https://github.com/TuguiDragos/Peel/releases/download/";
    const image = (release.assets || []).find((asset) => {
      return /\.dmg$/i.test(asset.name) && String(asset.browser_download_url).startsWith(prefix);
    });
    if (image) {
      document.querySelectorAll("[data-download]").forEach((link) => {
        link.href = image.browser_download_url;
      });
    }
    const version = String(release.tag_name || "").replace(/^v/, "");
    if (/^\d+(\.\d+)*$/.test(version)) {
      document.querySelectorAll("[data-version]").forEach((element) => {
        element.textContent = `Version ${version} · `;
      });
    }
  })
  .catch(() => {});
