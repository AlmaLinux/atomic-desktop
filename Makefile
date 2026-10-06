# ba0fde3d-bee7-4307-b97b-17d0d20aff50
SUDO = sudo
PODMAN = $(SUDO) podman

IMAGE_NAME ?= localhost/myimage
CONTAINER_FILE ?= ./Dockerfile
VARIANT ?= gnome

# The live ISO is defined in atomic-ci, so local builds are the same as the ones from CI
ATOMIC_CI_REF ?= v12.1
LIVE_URL ?= https://raw.githubusercontent.com/AlmaLinux/atomic-ci/$(ATOMIC_CI_REF)/.github/actions/build-iso/live
LIVE_IMAGE_NAME ?= $(IMAGE_NAME)-live
IMAGE_BUILDER ?= ghcr.io/osbuild/image-builder-cli:latest

QEMU_DISK_RAW ?= ./output/disk.raw
QEMU_DISK_QCOW2 ?= ./output/disk.qcow2
QEMU_ISO ?= ./output/install.iso

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

live_image:
	mkdir -p ./output/live
	curl -fsSL -o ./output/live/Containerfile $(LIVE_URL)/Containerfile
	curl -fsSL -o ./output/live/build.sh $(LIVE_URL)/build.sh
	chmod +x ./output/live/build.sh

	$(PODMAN) build \
		--pull=never \
		--cap-add=sys_admin \
		--security-opt=label=disable \
		--build-arg IMAGE_REF=$(IMAGE_NAME) \
		--build-arg ISO_NAME=$(notdir $(IMAGE_NAME)) \
		--build-arg ISO_LABEL= \
		-t $(LIVE_IMAGE_NAME) \
		-f ./output/live/Containerfile \
		./output/live

IMAGE_BUILDER_RUN = $(PODMAN) run \
		--rm \
		-it \
		--privileged \
		--pull=newer \
		--security-opt label=type:unconfined_t \
		-v ./output:/output \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		$(IMAGE_BUILDER) \
		build \
		--progress verbose \
		--output-dir /output

iso: live_image
	# The live image is the ISO, the image to install is embedded in it
	$(IMAGE_BUILDER_RUN) \
		--output-name install \
		--bootc-ref $(LIVE_IMAGE_NAME) \
		--bootc-installer-payload-ref $(IMAGE_NAME) \
		bootc-generic-iso

qcow2:
	mkdir -p ./output
	$(IMAGE_BUILDER_RUN) \
		--output-name disk \
		--bootc-ref $(IMAGE_NAME) \
		qcow2

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
	mkdir -p ./output
	# Make a disk to install to
	[[ ! -e $(QEMU_DISK_RAW) ]] && dd if=/dev/null of=$(QEMU_DISK_RAW) bs=1M seek=20480

	qemu-system-x86_64 \
		-M accel=kvm \
		-cpu host \
		-smp 2 \
		-m 6144 \
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
