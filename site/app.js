const copyText = {
  arch: {
    es: { title: "Arch, CachyOS o Manjaro", body: "Paquete AUR. Después, en Plasma: añade el widget KodexBar al panel.", cmd: "paru -S kodexbar-suite" },
    en: { title: "Arch, CachyOS, or Manjaro", body: "AUR package. Then on Plasma: add the KodexBar widget to the panel.", cmd: "paru -S kodexbar-suite" }
  },
  plasma: {
    es: { title: "Plasma 6 en otra distro", body: "No hay .deb/.rpm aún. Instalador en tu home, sin sudo. Luego añade el widget al panel.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" },
    en: { title: "Plasma 6 on another distro", body: "No native .deb/.rpm yet. User-local install, no sudo. Then add the widget to the panel.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" }
  },
  gnome: {
    es: { title: "GNOME o COSMIC", body: "No hay applet nativo. Se instala la bandeja. En GNOME activa la extensión AppIndicator. Debian/Ubuntu: gir1.2-ayatanaappindicator3-0.1. Fedora: libayatana-appindicator-gtk3.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh && kodexbar-tray --autostart-install" },
    en: { title: "GNOME or COSMIC", body: "No native applet. This installs the tray. On GNOME enable the AppIndicator extension. Debian/Ubuntu: gir1.2-ayatanaappindicator3-0.1. Fedora: libayatana-appindicator-gtk3.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh && kodexbar-tray --autostart-install" }
  },
  waybar: {
    es: { title: "Hyprland + Waybar", body: "Motor + módulo de Waybar. Pega el snippet con kodexbar-panel --waybar-snippet.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh && kodexbar-panel --waybar-snippet" },
    en: { title: "Hyprland + Waybar", body: "Engine + Waybar module. Paste the snippet from kodexbar-panel --waybar-snippet.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh && kodexbar-panel --waybar-snippet" }
  },
  xfce: {
    es: { title: "XFCE", body: "Generic Monitor en el panel. Command: kodexbar-panel --format text --pango. Periodo 60s.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" },
    en: { title: "XFCE", body: "Generic Monitor on the panel. Command: kodexbar-panel --format text --pango. 60s period.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" }
  },
  other: {
    es: { title: "Esto es para Linux", body: "KodexBar corre en Linux. El código y las releases están en GitHub.", cmd: "https://github.com/Karasowl/KodexBar-Suite" },
    en: { title: "This is a Linux app", body: "KodexBar runs on Linux. Source and releases live on GitHub.", cmd: "https://github.com/Karasowl/KodexBar-Suite" }
  }
};

let lang = "es";
let current = "plasma";

function guess() {
  const ua = navigator.userAgent || "";
  const plat = navigator.platform || "";
  const linux = /Linux/i.test(ua) || /Linux/i.test(plat);
  if (!linux) return "other";
  // Browser cannot see the DE. Prefer Arch only if the UA mentions it (rare).
  if (/CachyOS|Arch/i.test(ua)) return "arch";
  return "plasma";
}

function applyLang() {
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-es][data-en]").forEach((el) => {
    el.textContent = el.getAttribute("data-" + lang);
  });
  render();
}

function render() {
  const t = copyText[current][lang];
  document.getElementById("action-title").textContent = t.title;
  document.getElementById("action-body").textContent = t.body;
  document.getElementById("action-cmd").textContent = t.cmd;
  document.querySelectorAll("#pills button").forEach((b) => {
    b.classList.toggle("on", b.dataset.id === current);
  });
  const det = document.getElementById("detected");
  const guessed = guess();
  if (lang === "es") {
    det.textContent = guessed === "other"
      ? "Parece que no estás en Linux. Elige tu escritorio si sí lo estás."
      : "Linux detectado. Elige el escritorio si este no es.";
  } else {
    det.textContent = guessed === "other"
      ? "This does not look like Linux. Pick your desktop if it is."
      : "Linux detected. Switch desktop if this is wrong.";
  }
}

document.getElementById("lang").addEventListener("click", () => {
  lang = lang === "es" ? "en" : "es";
  applyLang();
});
document.getElementById("pills").addEventListener("click", (e) => {
  const id = e.target.dataset && e.target.dataset.id;
  if (!id) return;
  current = id;
  render();
});
document.getElementById("copy").addEventListener("click", async () => {
  const cmd = document.getElementById("action-cmd").textContent;
  try { await navigator.clipboard.writeText(cmd); } catch {}
});

current = guess() === "other" ? "other" : (guess() === "arch" ? "arch" : "plasma");
applyLang();
