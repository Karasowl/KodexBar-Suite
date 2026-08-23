const copyText = {
  arch: {
    en: { title: "Arch, CachyOS, or Manjaro", body: "AUR package. Then on Plasma: add the KodexBar widget to the panel.", cmd: "paru -S kodexbar-suite" },
    es: { title: "Arch, CachyOS o Manjaro", body: "Paquete AUR. Después, en Plasma: añade el widget KodexBar al panel.", cmd: "paru -S kodexbar-suite" }
  },
  plasma: {
    en: { title: "Plasma 6 on another distro", body: "No native .deb/.rpm yet. User-local install, no sudo. Then add the widget to the panel.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" },
    es: { title: "Plasma 6 en otra distro", body: "No hay .deb/.rpm aún. Instalador en tu home, sin sudo. Luego añade el widget al panel.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" }
  },
  gnome: {
    en: { title: "GNOME or COSMIC", body: "No native applet. This installs the tray. On GNOME enable the AppIndicator extension. Debian/Ubuntu: gir1.2-ayatanaappindicator3-0.1. Fedora: libayatana-appindicator-gtk3.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh && kodexbar-tray --autostart-install" },
    es: { title: "GNOME o COSMIC", body: "No hay applet nativo. Se instala la bandeja. En GNOME activa la extensión AppIndicator. Debian/Ubuntu: gir1.2-ayatanaappindicator3-0.1. Fedora: libayatana-appindicator-gtk3.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh && kodexbar-tray --autostart-install" }
  },
  waybar: {
    en: { title: "Hyprland + Waybar", body: "Engine + Waybar module. Paste the snippet from kodexbar-panel --waybar-snippet.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh && kodexbar-panel --waybar-snippet" },
    es: { title: "Hyprland + Waybar", body: "Motor + módulo de Waybar. Pega el snippet con kodexbar-panel --waybar-snippet.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh && kodexbar-panel --waybar-snippet" }
  },
  xfce: {
    en: { title: "XFCE", body: "Generic Monitor on the panel. Command: kodexbar-panel --format text --pango. 60s period.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" },
    es: { title: "XFCE", body: "Generic Monitor en el panel. Command: kodexbar-panel --format text --pango. Periodo 60s.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" }
  },
  other: {
    en: { title: "This is a Linux app", body: "KodexBar runs on Linux. Source and releases live on GitHub.", cmd: "https://github.com/Karasowl/KodexBar-Suite" },
    es: { title: "Esto es para Linux", body: "KodexBar corre en Linux. El código y las releases están en GitHub.", cmd: "https://github.com/Karasowl/KodexBar-Suite" }
  }
};

const pillLabels = {
  en: { arch: "Arch / CachyOS", plasma: "Plasma 6", gnome: "GNOME / COSMIC", waybar: "Hyprland / Waybar", xfce: "XFCE", other: "Other" },
  es: { arch: "Arch / CachyOS", plasma: "Plasma 6", gnome: "GNOME / COSMIC", waybar: "Hyprland / Waybar", xfce: "XFCE", other: "Otro" }
};

let lang = "en";
let current = "plasma";

function guess() {
  const ua = navigator.userAgent || "";
  const plat = navigator.platform || "";
  const linux = /Linux/i.test(ua) || /Linux/i.test(plat);
  if (!linux) return "other";
  if (/CachyOS|Arch/i.test(ua)) return "arch";
  return "plasma";
}

function applyLang() {
  document.documentElement.lang = lang;
  document.getElementById("lang").textContent = lang === "en" ? "ES" : "EN";
  document.querySelectorAll("[data-en][data-es]").forEach((el) => {
    el.textContent = el.getAttribute("data-" + lang);
  });
  const pills = document.getElementById("pills");
  pills.innerHTML = "";
  Object.keys(pillLabels.en).forEach((id) => {
    const b = document.createElement("button");
    b.type = "button";
    b.dataset.id = id;
    b.textContent = pillLabels[lang][id];
    pills.appendChild(b);
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
  if (lang === "en") {
    det.textContent = guessed === "other"
      ? "This does not look like Linux. Pick your desktop if it is."
      : "Linux detected. Switch desktop if this is wrong.";
  } else {
    det.textContent = guessed === "other"
      ? "Parece que no estás en Linux. Elige tu escritorio si sí lo estás."
      : "Linux detectado. Elige el escritorio si este no es.";
  }
}

document.getElementById("lang").addEventListener("click", () => {
  lang = lang === "en" ? "es" : "en";
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

current = guess();
applyLang();
