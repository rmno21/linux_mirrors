

# Linux Mirrors (IranMirrors.sh)

A cross‑distribution, smart mirror manager designed for Linux users operating under Iran's internet blackout. It automatically tests and selects the fastest accessible local mirrors for your distribution, ensuring your system can be updated and maintained even when international access is severed.

## ✨ Features

- **🖥️ Multi‑Distribution Support** – Auto‑detects and configures sources for APT (Debian/Ubuntu), YUM/DNF (RHEL/Rocky/AlmaLinux), and Pacman (Arch/Manjaro).
- **⚡ Smart Testing** – Tests latency and availability of dozens of local mirrors using HTTP checks and ping, then selects the top 4 fastest options.
- **🛡️ Safe & Automatic Backups** – Creates a timestamped backup of your original sources before making any changes.
- **🔄 One‑Command Restore** – Easily revert to your previous configuration with the `--restore` flag.

## 🚀 Quick Start: One‑Line Install & Run

**As `root` or with `sudo`**, copy and paste this command into your terminal:

```bash
curl -s -o /tmp/IranMirrors.sh https://raw.githubusercontent.com/RMNO21/Linux_Mirrors/main/IranMirrors.sh && sudo bash /tmp/IranMirrors.sh
```

The script will:
1.  Detect your operating system.
2.  Test a curated list of Iranian and accessible local mirrors.
3.  Automatically update your source lists with the fastest ones.

## 🔧 Manual Usage

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/RMNO21/Linux_Mirrors.git
    cd Linux_Mirrors
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x IranMirrors.sh
    ```

3.  **Run the script as root:**
    ```bash
    sudo ./IranMirrors.sh
    ```

## 📋 How It Works

1.  **Backup**: Your current sources (e.g., `/etc/apt/sources.list` or `/etc/pacman.d/mirrorlist`) are backed up to `/var/backups/mirrorgpt/`.
2.  **Testing**: The script sends a lightweight HTTP probe to each mirror and measures response time.
3.  **Selection**: The four mirrors with the lowest latency and highest reliability are selected.
4.  **Update**: Your system’s source list is replaced with the new mirrors.
5.  **Finalize**: Run `apt update`, `yum update`, or `pacman -Syy` to refresh your package database.

## 🗺️ Included Mirrors

The script contains a curated, static list of active local mirrors within Iran or accessible via the national intranet. This list is regularly updated and includes providers such as:

- `mirror.shatel.ir`
- `repo-portal.ito.gov.ir`
- `arvancloud.ir`
- `linuxmirrors.ir`
- `repo.iut.ac.ir`

*(A full list can be found within the `MIRRORS_UBUNTU`, `MIRRORS_DEBIAN`, etc., arrays in the script.)*

## 🤝 Contributing

If you know of a new or updated local mirror that should be added to the list, please open an issue or submit a pull request. **Your contribution helps keep the community connected.**

## ⚖️ License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.

## 📡 Community & Awareness

#InternetShutdown #IranInternetShutdown #DigitalBlackoutIran #IranDigitalBlackout #Whitelisted_Line #IRanASignalProxy #SOSIran


