# T2 Linux Suspend Fix

Forked and inspired by:

- [deqrocks/T2Linux-Suspend-Fix](https://github.com/deqrocks/T2Linux-Suspend-Fix)
- [lucadibello/T2Linux-Suspend-Fix](https://github.com/lucadibello/T2Linux-Suspend-Fix)


**WARNING**: This works for me, it might not work for you. Please take caution and review this script as a whole before installing it, and adjust it to your needs. I will not be maintaining this other than for my own use.


## Supported Models

This suspend fix has been tested on the following MacBook Pro models with T2 security chips:

### MacBook Pro 16" (2019)

- CPU: 9th Gen Intel i7 | GPU: AMD 5300M 4GB | RAM: 64GB | SSD: 1TB
- Triple Boot: MacOS Tahoe 120GB | Windows 11 400GB | CachyOS 400GB
- Boot Manager: rEFInd
- Desktop: COSMIC

### MacBook Pro 13" (2020)

- CPU: 10th Gen Intel i7 | GPU: Intel iGPU | RAM: 32GB | SSD: 1TB
- Triple Boot: MacOS 120GB | Windows 11 400GB | CachyOS 400GB
- Boot Manager: rEFInd
- Desktop: Niri

Other T2 MacBook models may work but have not been tested. The installer automatically detects your hardware and only installs services needed for your specific configuration.


## Hardware Detection

The installer automatically detects your hardware configuration and stores it in `/etc/t2-suspend-fix/hardware.conf`. This allows services to be installed only for your specific setup (e.g., GMUX services are only installed on dual-GPU systems).


## Prerequisites

The installer will check for and require:
- `brightnessctl` - Backlight control
- `swayidle` - Idle monitoring (for keyboard backlight auto-off)
- `wpctl` - PipeWire control


## Installation

```bash
git clone https://github.com/benstaker/T2Linux-Suspend-Fix.git
cd T2Linux-Suspend-Fix
./t2-suspend-fix.sh
```


## Kernel Arguments

Recommended kernel parameters for T2 MacBooks:

```
i915.enable_guc=3 mem_sleep_default=deep pcie_aspm=off intel_iommu=on iommu=pt pcie_ports=compat
```


## Migration Notes for Existing Users

If upgrading from an earlier version:

1. **Uninstall first**: Run `./t2-suspend-fix.sh` and select uninstall
2. **Install fresh**: Run `./t2-suspend-fix.sh` and select install
3. The new hardware detection will automatically configure services for your model

Legacy script names are still cleaned up during uninstall for backward compatibility.


### Additional Services Installed:

1. [NoaHimesaka1873/tiny-dfr-arch](https://github.com/NoaHimesaka1873/tiny-dfr-arch)
2. brightnessctl (via pacman)
3. [auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq)


### Drivers:

1. [NoaHimesaka1873/linux-t2-arch](https://github.com/NoaHimesaka1873/linux-t2-arch)


### Audio Configuration (16" MacBook only):

1. [ngodn/linux-t2-mbp16_1-arch-audio-setup](https://github.com/ngodn/linux-t2-mbp16_1-arch-audio-setup)


## Performance

### My experience:

1. Suspends within ~4 seconds, can hear the fans go off completely.
2. Waking: Screen on ~14 seconds + ~4 seconds for restarting display.
3. Battery life consumed when suspended around 0.5% - 0.75% per hour.


## Known Issues

1. If you force shutdown, you will need to boot into MacOS, then restart from the login screen and then boot back into linux. Otherwise some devices do not work.
2. Using `pcie_ports=native` slows waking by a lot.
3. Tried using [deqrocks/apple-bce-drv](https://github.com/deqrocks/apple-bce-drv), however this caused issues with the touchbar working after waking.
4. Putting the laptop to sleep whilst USB-C charging prevents the touchbar waking up - unplugging and then suspending / waking fixes this.
5. Plugging in a USB-C charger whilst the lid is closed prevents the touchbar waking up - unplugging and then suspending / waking fixes this.
6. Using `intel_pstate=disable` to disable intel's governor slows waking by a lot.
