const copyText = {
  arch: {
    en: { title: "Arch, CachyOS, or Manjaro", body: "AUR package with native Claude, Codex, Cursor, Grok, OpenCode Go, Hermes, and Devin quotas. Then on Plasma: add the KodexBar widget to the panel.", cmd: "paru -S kodexbar-suite" },
    es: { title: "Arch, CachyOS o Manjaro", body: "Paquete AUR con cuotas nativas de Claude, Codex, Cursor, Grok, OpenCode Go, Hermes y Devin. Después, en Plasma: añade el widget KodexBar al panel.", cmd: "paru -S kodexbar-suite" }
  },
  debian: {
    en: { title: "Debian or Ubuntu", body: "Native DEB with the same Claude, Codex, Cursor, Grok, OpenCode Go, Hermes, and Devin quotas. Then on Plasma: add the KodexBar widget to the panel.", cmd: "curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/kodexbar-suite_0.12.10-1_all.deb && sudo apt install ./kodexbar-suite_0.12.10-1_all.deb" },
    es: { title: "Debian o Ubuntu", body: "DEB nativo con las mismas cuotas de Claude, Codex, Cursor, Grok, OpenCode Go, Hermes y Devin. Después, en Plasma: añade el widget KodexBar al panel.", cmd: "curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/kodexbar-suite_0.12.10-1_all.deb && sudo apt install ./kodexbar-suite_0.12.10-1_all.deb" }
  },
  fedora: {
    en: { title: "Fedora or RHEL 10", body: "Native RPM with the same Claude, Codex, Cursor, Grok, OpenCode Go, Hermes, and Devin quotas. RHEL 9, AlmaLinux 9, and Rocky 9 use the .el9 RPM from GitHub Releases.", cmd: "curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/kodexbar-suite-0.12.10-1.noarch.rpm && sudo dnf install ./kodexbar-suite-0.12.10-1.noarch.rpm" },
    es: { title: "Fedora o RHEL 10", body: "RPM nativo con las mismas cuotas de Claude, Codex, Cursor, Grok, OpenCode Go, Hermes y Devin. RHEL 9, AlmaLinux 9 y Rocky 9 usan el RPM .el9 de GitHub Releases.", cmd: "curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/kodexbar-suite-0.12.10-1.noarch.rpm && sudo dnf install ./kodexbar-suite-0.12.10-1.noarch.rpm" }
  },
  windows: {
    en: { title: "Windows 10 or 11", body: "Per-user tray installer with the same Claude, Codex, Cursor, Grok, OpenCode Go, Hermes, and Devin quotas. No administrator rights. A portable zip is on the same release page.", cmd: "https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/KodexBar-Suite-0.12.10-windows-setup.exe" },
    es: { title: "Windows 10 u 11", body: "Instalador de bandeja por usuario con las mismas cuotas de Claude, Codex, Cursor, Grok, OpenCode Go, Hermes y Devin. No pide administrador. El zip portable está en la misma página de release.", cmd: "https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/KodexBar-Suite-0.12.10-windows-setup.exe" }
  },
  plasma: {
    en: { title: "Plasma 6 on another distro", body: "Native DEB and RPM packages are available in GitHub Releases. This portable option installs without sudo. Then add the widget to the panel.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" },
    es: { title: "Plasma 6 en otra distro", body: "Hay paquetes DEB y RPM nativos en GitHub Releases. Esta opción portable instala sin sudo. Luego añade el widget al panel.", cmd: "git clone https://github.com/Karasowl/KodexBar-Suite.git && cd KodexBar-Suite && ./install.sh" }
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
    en: { title: "Linux or Windows", body: "KodexBar runs on Linux and Windows. Source, DEB, RPM, Plasma, and Windows downloads live on GitHub.", cmd: "https://github.com/Karasowl/KodexBar-Suite/releases/latest" },
    es: { title: "Linux o Windows", body: "KodexBar corre en Linux y Windows. El código y las descargas DEB, RPM, Plasma y Windows están en GitHub.", cmd: "https://github.com/Karasowl/KodexBar-Suite/releases/latest" }
  }
};

const pillLabels = {
  en: { arch: "Arch / CachyOS", debian: "Debian / Ubuntu", fedora: "Fedora / RHEL", windows: "Windows", plasma: "Plasma 6", gnome: "GNOME / COSMIC", waybar: "Hyprland / Waybar", xfce: "XFCE", other: "Other" },
  es: { arch: "Arch / CachyOS", debian: "Debian / Ubuntu", fedora: "Fedora / RHEL", windows: "Windows", plasma: "Plasma 6", gnome: "GNOME / COSMIC", waybar: "Hyprland / Waybar", xfce: "XFCE", other: "Otro" }
};

let lang = "en";
let current = "plasma";

function guess() {
  const ua = navigator.userAgent || "";
  const plat = navigator.platform || "";
  if (/Windows|Win32|Win64/i.test(ua) || /^Win/i.test(plat)) return "windows";
  const linux = /Linux/i.test(ua) || /Linux/i.test(plat);
  if (!linux) return "other";
  if (/CachyOS|Arch/i.test(ua)) return "arch";
  if (/Debian|Ubuntu/i.test(ua)) return "debian";
  if (/Fedora|Red Hat|Rocky|AlmaLinux|CentOS/i.test(ua)) return "fedora";
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
    det.textContent = guessed === "windows"
      ? "Windows detected. The tray installer is below."
      : guessed === "other"
        ? "This does not look like Linux or Windows. Pick your system if it is."
        : "Linux detected. Switch desktop if this is wrong.";
  } else {
    det.textContent = guessed === "windows"
      ? "Windows detectado. El instalador de la bandeja está abajo."
      : guessed === "other"
        ? "Parece que no estás en Linux ni Windows. Elige tu sistema si sí lo estás."
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
