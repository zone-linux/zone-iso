FROM archlinux:latest

# Full upgrade first: a partially upgraded build container is the most common
# source of archiso failures.
RUN pacman -Syu --noconfirm --needed \
        archiso \
        dosfstools \
        e2fsprogs \
        erofs-utils \
        grub \
        libarchive \
        libisoburn \
        mkinitcpio \
        mtools \
        openssl \
        squashfs-tools \
        syslinux \
    && pacman -Scc --noconfirm

WORKDIR /build
