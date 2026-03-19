# T2 Linux Suspend Fix

Forked and inspired by:

- [deqrocks/T2Linux-Suspend-Fix](https://github.com/deqrocks/T2Linux-Suspend-Fix)
- [lucadibello/T2Linux-Suspend-Fix](https://github.com/lucadibello/T2Linux-Suspend-Fix)


**WARNING**: This works for me, it might not work for you. Please take caution and review this script as a whole before installing it, and adjust it to your needs. I will not be maintaining this other than for my own use.


### Modified this to work with my setup:

- MacBook Pro 2019 16": Intel i7 2.6Ghz | AMD 5300M 4GB | 64GB RAM | 1TB SSD
- Triple Boot: MacOS Tahoe 120GB | Windows 11 400GB | CachyOS 400GB
- Boot Manager: rEFInd
- Desktop: COSMIC


### Kernel arguments:

- `i915.enable_guc=3`
- `mem_sleep_default=deep`
- `pcie_aspm=off`
- `intel_iommu=on`
- `iommu=pt`
- `pcie_ports=compat`
- ...defaults...


### Services installed:

1. [NoaHimesaka1873/tiny-dfr-arch](https://github.com/NoaHimesaka1873/tiny-dfr-arch)
2. brightnessctl (via pacman)
2. [auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq)


### Drivers:

1. [NoaHimesaka1873/linux-t2-arch](https://github.com/NoaHimesaka1873/linux-t2-arch)


### Configuration:

1. [ngodn/linux-t2-mbp16_1-arch-audio-setup](https://github.com/ngodn/linux-t2-mbp16_1-arch-audio-setup)



### My experience:

1. Suspends within ~4 seconds, can hear the fans go off completely.
2. Waking: Screen on ~14 seconds + ~4 seconds for restarting display.
3. Battery life consumed when suspended around 0.5% - 0.75% per hour.


### Things to know:

1. If you force shutdown, you will need to boot into MacOS, then restart from the login screen and then boot back into linux. Otherwise some devices do not work.
2. I have tried using `pcie_ports=native`, but this slows waking by a lot.
3. Tried using [deqrocks/apple-bce-drv](https://github.com/deqrocks/apple-bce-drv), however this caused issues with the touchbar working after waking.
4. Putting the laptop to sleep whilst USB-C charging prevents the touchbar waking up - unplugging and then suspending / waking fixes this.
5. Plugging in a USB-C charger whilst the lid is closed prevents the touchbar waking up - unplugging and then suspending / waking fixes this.
6. Using `intel_pstate=disable` to disable intel's governor slows waking by a lot.