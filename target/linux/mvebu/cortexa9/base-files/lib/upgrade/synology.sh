. /lib/functions.sh

# The DS216j keeps the kernel and the rootfs in two separate partitions.
# The upgrade image is the concatenation of both: the kernel padded to
# 4 MB, followed by the rootfs.
synology_ds216j_do_upgrade() {
	local kernel_part="$(find_mtd_part "kernel")"
	local rootfs_part="$(find_mtd_part "rootfs")"

	if [ -z "$kernel_part" ]; then
		echo "ERROR: MTD device \"kernel\" not found"
		umount -a
		reboot -f
	fi

	if [ -z "$rootfs_part" ]; then
		echo "ERROR: MTD device \"rootfs\" not found"
		umount -a
		reboot -f
	fi

	# The flash may hold the original Synology firmware instead of
	# OpenWrt. Its rootfs partition does not start with a squashfs, and
	# overwriting it would destroy the firmware. Check before writing
	# anything.
	if ! dd if="$rootfs_part" bs=4 count=1 2>/dev/null | grep -q hsqs; then
		echo "ERROR: the rootfs partition holds no squashfs - the flash"
		echo "       does not belong to OpenWrt, leaving it untouched."
		echo "       Boot OpenWrt from the USB stick to update it."
		return 1
	fi

	# A system that was booted from the USB stick must never write to
	# the flash: it can hold the original Synology firmware, and the
	# upgrade of such a system writes to the stick (see usb-update.sh).
	if grep -q "root=PARTLABEL=openwrt-root" /proc/cmdline 2>/dev/null; then
		echo "ERROR: this system was booted from the USB stick - the"
		echo "       SPI flash is left untouched. Use usb-update.sh to"
		echo "       update the root filesystem on the stick."
		return 1
	fi

	# "mtd write" erases every block before it writes it, a plain dd
	# fails on a flash that is not erased.
	dd if="$1" bs=1M count=4 | mtd write - kernel

	# The rootfs partition holds the squashfs at its beginning, the
	# kernel uses the space behind it as the JFFS2 overlay. Erase the
	# partition before writing, otherwise a growing squashfs runs into
	# the old overlay. The overlay is recreated empty by the kernel, the
	# configuration is kept in the extroot on the USB disk.
	mtd erase rootfs
	dd if="$1" bs=1M skip=4 | mtd write - rootfs
}
