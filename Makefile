SUDO = sudo
PODMAN = $(SUDO) podman

IMAGE_NAME ?= localhost/myimage
CONTAINER_FILE ?= ./Dockerfile
VARIANT ?= gnome
IMAGE_CONFIG ?= ./iso.toml

IMAGE_TYPE ?= iso
QEMU_DISK_RAW ?= ./output/disk.raw
QEMU_DISK_QCOW2 ?= ./output/qcow2/disk.qcow2
QEMU_ISO ?= ./output/bootiso/install.iso

.ONESHELL:

clean:
	$(SUDO) rm -rf ./output

image:
	$(PODMAN) build \
		--security-opt=label=disable \
		--cap-add=all \
		--device /dev/fuse \
		--build-arg IMAGE_NAME=$(IMAGE_NAME) \
		--build-arg IMAGE_REGISTRY=localhost \
		--build-arg VARIANT=$(VARIANT) \
		-t $(IMAGE_NAME) \
		-f $(CONTAINER_FILE) \
		.

bib_image:
	$(SUDO) rm -rf ./output
	mkdir -p ./output

	cp $(IMAGE_CONFIG) ./output/config.toml
	# Don't bother trying to switch to a new image, this is just for local testing
	sed -i '/bootc switch/d' ./output/config.toml

	if [ "$(IMAGE_TYPE)" = "iso" ]; then
		LIBREPO=False;
	else
		LIBREPO=True;
	fi;

	$(PODMAN) run \
		--rm \
		-it \
		--privileged \
		--pull=newer \
		--security-opt label=type:unconfined_t \
		-v ./output:/output \
		-v ./output/config.toml:/config.toml:ro \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		quay.io/centos-bootc/bootc-image-builder:latest \
		--type iso \
		--use-librepo=$$LIBREPO \
		--progress verbose \
		$(IMAGE_NAME)

iso:
	make bib_image IMAGE_TYPE=iso

qcow2:
	make bib_image IMAGE_TYPE=qcow2

run-qemu-qcow:
	qemu-system-x86_64 \
		-M accel=kvm \
		-cpu host \
		-smp 2 \
		-m 4096 \
		-bios /usr/share/OVMF/x64/OVMF.4m.fd \
		-serial stdio \
		-snapshot $(QEMU_DISK_QCOW2)

run-qemu-iso:
	# Make a disk to install to
	[[ ! -e $(QEMU_DISK_RAW) ]] && dd if=/dev/null of=$(QEMU_DISK_RAW) bs=1M seek=20480

	qemu-system-x86_64 \
		-M accel=kvm \
		-cpu host \
		-smp 2 \
		-m 4096 \
		-bios /usr/share/OVMF/x64/OVMF.4m.fd \
		-serial stdio \
		-boot d \
		-cdrom $(QEMU_ISO) \
		-hda $(QEMU_DISK_RAW)

run-qemu:
	qemu-system-x86_64 \
		-M accel=kvm \
		-cpu host \
		-smp 2 \
		-m 4096 \
		-bios /usr/share/OVMF/x64/OVMF.4m.fd \
		-serial stdio \
		-hda $(QEMU_DISK_RAW)
