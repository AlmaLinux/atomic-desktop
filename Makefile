SUDO = sudo
PODMAN = $(SUDO) podman

IMAGE_NAME ?= localhost/myimage
TAG ?= latest
CONTAINER_FILE ?= ./Dockerfile
VARIANT ?= gnome
IMAGE_CONFIG ?= ./iso.toml

IMAGE_TYPE ?= iso
QEMU_DISK_RAW ?= ./output/disk.raw
QEMU_DISK_QCOW2 ?= ./output/qcow2/disk.qcow2
QEMU_ISO ?= ./output/bootiso/install.iso

RECHUNKER_IMAGE ?= ghcr.io/hhd-dev/rechunk:latest
BUILDDIR ?= ./output/rechunk
OUT_NAME=$(BUILDDIR)/$(IMAGE_NAME).tar



.ONESHELL:

# Clean up output directory
clean:
	$(SUDO) rm -rf ./output

# Build the container image
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

# Build base image builder (bib) image
bib_image:
	$(SUDO) rm -rf ./output/$(IMAGE_TYPE)
	mkdir -p ./output/$(IMAGE_TYPE)

	cp $(IMAGE_CONFIG) ./output/config.toml
	# Don't bother trying to switch to a new image, this is just for local testing
	sed -i '/bootc switch/d' ./output/config.toml

	if [ "$(IMAGE_TYPE)" = "iso" ]; then \
		LIBREPO=False; \
	else \
		LIBREPO=True; \
	fi; \
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
		--type $(IMAGE_TYPE) \
		--use-librepo=$$LIBREPO \
		--progress verbose \
		$(IMAGE_NAME)

# Create an ISO image
iso:
	$(MAKE) bib_image IMAGE_TYPE=iso

# Create a QCOW2 image
qcow2:
	$(MAKE) bib_image IMAGE_TYPE=qcow2

# Run QEMU with the QCOW2 disk image
run-qemu-qcow:
	qemu-system-x86_64 \
		-M accel=kvm \
		-cpu host \
		-smp 2 \
		-m 4096 \
		-bios /usr/share/OVMF/x64/OVMF.4m.fd \
		-serial stdio \
		-snapshot $(QEMU_DISK_QCOW2)

# Run QEMU to install from ISO
run-qemu-iso:
	mkdir -p ./output
	# Make a disk to install to if it doesn't exist
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

# Run QEMU with the raw disk image
run-qemu:
	qemu-system-x86_64 \
		-M accel=kvm \
		-cpu host \
		-smp 2 \
		-m 4096 \
		-bios /usr/share/OVMF/x64/OVMF.4m.fd \
		-serial stdio \
		-hda $(QEMU_DISK_RAW)

# Perform rechunking operations using hhd-rechunker
hhd-rechunk:
	$(SUDO) rm -rf $(BUILDDIR)
	mkdir -p $(BUILDDIR)/$(IMAGE_NAME)

	# Get version label from the image
	VERSION_LABEL=$$( $(PODMAN) inspect $(IMAGE_NAME):$(TAG) --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' )
	echo "Version label: $$VERSION_LABEL"
	# Get all labels from the image
	LABELS_FROM_IMAGE=$$( $(PODMAN) inspect $(IMAGE_NAME):$(TAG) | jq -r '.[].Config.Labels | to_entries | map("\(.key)=\(.value|tostring)")|.[]' )
	echo "Labels from image: $$LABELS_FROM_IMAGE"

	# Create a temporary container to mount its filesystem
	CREF=$$( $(PODMAN) create $(IMAGE_NAME):$(TAG) bash )
	echo "Created temporary container: $$CREF"
	# Mount the container's filesystem
	MOUNT=$$( $(PODMAN) mount $$CREF )
	echo "Mounted container filesystem at: $$MOUNT"
	$(PODMAN) pull --retry 3 "$(RECHUNKER_IMAGE)"

	# Run the first rechunking step (pruning)
	$(PODMAN) run --rm \
        --security-opt label=disable \
        --volume "$$MOUNT":/var/tree \
        --env TREE=/var/tree \
        --user 0:0 \
        "$(RECHUNKER_IMAGE)" \
        /sources/rechunk/1_prune.sh

    # Run the second rechunking step (creating the OSTree repository)
	$(PODMAN) run --rm \
        --security-opt label=disable \
        --volume "$$MOUNT":/var/tree \
        --volume "cache_ostree:/var/ostree" \
        --env TREE=/var/tree \
        --env REPO=/var/ostree/repo \
        --env RESET_TIMESTAMP=1 \
        --user 0:0 \
        "$(RECHUNKER_IMAGE)" \
        /sources/rechunk/2_create.sh

    # Unmount and remove the temporary container
	$(PODMAN) unmount "$$CREF"
	$(PODMAN) rm "$$CREF"
	
    # Run the third rechunking step (chunking and archiving)
    # Note the corrected volume mounts and environment variables below
	$(PODMAN) run --rm \
        --security-opt label=disable \
        --volume "$(BUILDDIR)/$(IMAGE_NAME):/workspace" \
        --volume "/var/lib/containers/storage:/var/lib/containers/storage:ro" \
        --volume ".:/var/git" \
        --volume cache_ostree:/var/ostree \
        --env REPO=/var/ostree/repo \
        --env LABELS="$${LABELS:-$${LABELS_FROM_IMAGE}}" \
        --env PREV_REF="$(IMAGE_NAME):$(TAG)" \
        --env OUT_NAME="/workspace/image.tar" \
        --env VERSION="$$VERSION_LABEL" \
        --env VERSION_FN=/workspace/version.txt \
        --env OUT_REF="oci-archive:/workspace/image.tar" \
        --env GIT_DIR="/var/git" \
        --user 0:0 \
        "$(RECHUNKER_IMAGE)" \
        /sources/rechunk/3_chunk.sh

    # Clean up cache volume and old image, then load new image
    # Note the corrected path for the output tar file
	$(PODMAN) volume rm cache_ostree
	[ -f "$(BUILDDIR)/$(IMAGE_NAME)/image.tar" ] && $(PODMAN) rmi "$(IMAGE_NAME):$(TAG)" || true
	$(PODMAN) load -i $(BUILDDIR)/$(IMAGE_NAME)/image.tar
