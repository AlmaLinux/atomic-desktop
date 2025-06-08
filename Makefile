# Original Variables
SUDO = sudo
PODMAN = $(SUDO) podman

IMAGE_NAME ?= localhost/almalinux-atomic-desktop
CONTAINER_FILE ?= ./Dockerfile
VARIANT ?= gnome
IMAGE_CONFIG ?= ./iso.toml
ALMA_VERSION ?= 10
BASE_IMAGE ?= quay.io/almalinuxorg/almalinux-bootc:$(ALMA_VERSION)

IMAGE_TYPE ?= iso # Default for bib_image, overridden by specific targets

# Disk/Image Paths
QEMU_DISK_QCOW2 ?= ./output/qcow2/disk.qcow2
QEMU_ISO ?= ./output/bootiso/install.iso
QEMU_DISK_RAW ?= ./output/disk.raw
ISO_INSTALL_TARGET_DISK ?= ./output/install_target.raw

# Libvirt VM names
VM_QCOW_NAME ?= $(subst /,-,$(IMAGE_NAME))-qcow-vm
VM_ISO_NAME ?= $(subst /,-,$(IMAGE_NAME))-iso-installer-vm
VM_RAW_NAME ?= $(subst /,-,$(IMAGE_NAME))-raw-built-vm

OS_VARIANT ?= almalinux$(ALMA_VERSION)

.ONESHELL:

# --- Generic Image Building Targets ---
clean:
	$(SUDO) rm -rf ./output

# Optional: Target to check if container image exists and build if not or if old
ifimage:
	@IMAGE_ID=$$($(PODMAN) images --format "{{.Repository}} {{.ID}}" | awk '/^$(IMAGE_NAME)$$/ {print $$2}'); \
	if [ -n "$$IMAGE_ID" ]; then \
	    CREATED=$$($(PODMAN) inspect --format '{{.Created}}' $$IMAGE_ID); \
	    CREATED_EPOCH=$$(date -d "$$CREATED" +%s); \
	    NOW_EPOCH=$$(date +%s); \
	    AGE_HOURS=$$(( (NOW_EPOCH - CREATED_EPOCH) / 3600 )); \
	    if [ "$$AGE_HOURS" -lt 24 ]; then \
	        echo "Container image $(IMAGE_NAME) exists and is newer than 24 hours."; \
	        exit 0; \
	    else \
	        echo "Container image $(IMAGE_NAME) exists but is older than 24 hours. Rebuilding..."; \
	        $(MAKE) image; \
	    fi; \
	else \
	    echo "Container image $(IMAGE_NAME) not found. Building..."; \
	    $(MAKE) image; \
	fi

# Builds the base container image
image:
	$(PODMAN) build \
	    --security-opt=label=disable \
	    --cap-add=all \
	    --device /dev/fuse \
	    --build-arg BASE_IMAGE=$(BASE_IMAGE) \
	    --build-arg IMAGE_NAME=$(IMAGE_NAME) \
	    --build-arg IMAGE_REGISTRY=localhost \
	    --build-arg VARIANT=$(VARIANT) \
	    -t $(IMAGE_NAME) \
	    -f $(CONTAINER_FILE) \
	    .

# Generic target to run bootc-image-builder
bib_image: ifimage # Ensures container image is up-to-date or built
	$(SUDO) rm -rf ./output/config.toml
	@echo "Cleaning previous $(IMAGE_TYPE) output..."
	@if [ "$(IMAGE_TYPE)" = "raw" ]; then \
	    $(SUDO) rm -f $(QEMU_DISK_RAW); \
	elif [ "$(IMAGE_TYPE)" = "iso" ]; then \
	    $(SUDO) rm -rf ./output/bootiso; \
	elif [ "$(IMAGE_TYPE)" = "qcow2" ]; then \
	    $(SUDO) rm -rf ./output/qcow2; \
	fi
	mkdir -p ./output/qcow2 ./output/bootiso
	cp $(IMAGE_CONFIG) ./output/config.toml
	sed -i '/bootc switch/d' ./output/config.toml # No bootc switch for local testing
	@echo "Running bootc-image-builder with IMAGE_TYPE=$(IMAGE_TYPE)..."
	$(PODMAN) run \
	    --rm -it --privileged --pull=newer \
	    --security-opt label=type:unconfined_t \
	    -v ./output:/output \
	    -v ./output/config.toml:/config.toml:ro \
	    -v /var/lib/containers/storage:/var/lib/containers/storage \
	    quay.io/centos-bootc/bootc-image-builder:latest \
	    --type $(IMAGE_TYPE) --use-librepo=False --progress verbose \
	    $(IMAGE_NAME)
	@echo "bootc-image-builder finished for $(IMAGE_TYPE)."

# --- Specific Image Type Build Targets ---
qcow2: ; $(MAKE) bib_image IMAGE_TYPE=qcow2
iso: ; $(MAKE) bib_image IMAGE_TYPE=iso
build-image-raw: ; $(MAKE) bib_image IMAGE_TYPE=raw

# --- Helper target to create empty raw disk for ISO installation ---
ensure_iso_install_target_disk:
	@if [ ! -e "$(ISO_INSTALL_TARGET_DISK)" ]; then \
	    echo "Creating empty raw disk $(ISO_INSTALL_TARGET_DISK) (20GB)..."; \
	    mkdir -p $$(dirname $(ISO_INSTALL_TARGET_DISK)); \
	    dd if=/dev/zero of=$(ISO_INSTALL_TARGET_DISK) bs=1M count=0 seek=20480; \
	else \
	    echo "Raw disk $(ISO_INSTALL_TARGET_DISK) already exists."; \
	fi

# --- SELinux Helper Target ---
selinux-allow-libvirt-homedirs:
	@echo "Attempting to set SELinux boolean 'virt_home_dirs' to 'on' (persistent)."
	@echo "Requires 'policycoreutils-python-utils' or similar."
	$(SUDO) setsebool -P virt_home_dirs on
	@echo "'virt_home_dirs' boolean set."

# --- Common virt-install options ---
define VIRT_INSTALL_BASE
$(SUDO) virt-install \
    --memory 4096 \
    --vcpus 2 \
    --boot uefi \
    --osinfo name=$(OS_VARIANT),require=off \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole \
    --check path_in_use=off
endef

# --- VM Definition and Lifecycle Macros ---
# $(1): VM Name, $(2): Disk Path, $(3): Disk Format, $(4): Extra virt-install args for import
define DEFINE_VM_IMPORT
@echo "Defining VM: $(1) from $(2)"
@echo "Attempting to set SELinux context 'virt_image_t' on $(2)..."
-$(SUDO) chcon -t virt_image_t $$(readlink -f $(2)) || echo "Warning: Failed to set SELinux context."
-$(SUDO) virsh destroy $(1) > /dev/null 2>&1 || true
-$(SUDO) virsh undefine $(1) --remove-all-storage > /dev/null 2>&1 || true
$(VIRT_INSTALL_BASE) \
    --name $(1) \
    --disk path=$$(readlink -f $(2)),format=$(3),bus=virtio,cache=none \
    $(4)
endef

# --- QCOW2 VM ---
define-vm-qcow: qcow2
	$(call DEFINE_VM_IMPORT,$(VM_QCOW_NAME),$(QEMU_DISK_QCOW2),qcow2,--import)
start-vm-qcow: define-vm-qcow ; @echo "Starting VM: $(VM_QCOW_NAME)..."; $(SUDO) virsh start $(VM_QCOW_NAME)
console-vm-qcow: ; @echo "Console for $(VM_QCOW_NAME)..."; $(SUDO) virsh console $(VM_QCOW_NAME)
stop-vm-qcow: ; @echo "Stopping VM: $(VM_QCOW_NAME)..."; -$(SUDO) virsh shutdown $(VM_QCOW_NAME) --timeout 10 || $(SUDO) virsh destroy $(VM_QCOW_NAME)
destroy-vm-qcow: stop-vm-qcow ; @echo "Undefining VM: $(VM_QCOW_NAME)..."; -$(SUDO) virsh undefine $(VM_QCOW_NAME) > /dev/null 2>&1

# --- ISO Installer VM ---
define-vm-iso-installer: iso ensure_iso_install_target_disk
	@echo "Defining ISO Installer VM: $(VM_ISO_NAME) with ISO $(QEMU_ISO) to $(ISO_INSTALL_TARGET_DISK)"
	@echo "Attempting to set SELinux context 'virt_image_t' on $(ISO_INSTALL_TARGET_DISK)..."
	-$(SUDO) chcon -t virt_image_t $$(readlink -f $(ISO_INSTALL_TARGET_DISK)) || echo "Warning: Failed to set SELinux context on target disk."
	-$(SUDO) virsh destroy $(VM_ISO_NAME) > /dev/null 2>&1 || true
	-$(SUDO) virsh undefine $(VM_ISO_NAME) --remove-all-storage > /dev/null 2>&1 || true
	$(VIRT_INSTALL_BASE) \
	    --name $(VM_ISO_NAME) \
	    --disk path=$$(readlink -f $(ISO_INSTALL_TARGET_DISK)),format=raw,bus=virtio,cache=none \
	    --cdrom $$(readlink -f $(QEMU_ISO)) \
	    --events on_poweroff=preserve
start-vm-iso-installer: define-vm-iso-installer ; @echo "Starting VM: $(VM_ISO_NAME)..."; $(SUDO) virsh start $(VM_ISO_NAME)
console-vm-iso-installer: ; @echo "Console for $(VM_ISO_NAME)..."; $(SUDO) virsh console $(VM_ISO_NAME)
stop-vm-iso-installer: ; @echo "Stopping VM: $(VM_ISO_NAME)..."; -$(SUDO) virsh shutdown $(VM_ISO_NAME) --timeout 10 || $(SUDO) virsh destroy $(VM_ISO_NAME)
destroy-vm-iso-installer: stop-vm-iso-installer ; @echo "Undefining VM: $(VM_ISO_NAME)..."; -$(SUDO) virsh undefine $(VM_ISO_NAME) > /dev/null 2>&1

# --- Built Raw Disk VM ---
define-vm-raw-boot: build-image-raw
	$(call DEFINE_VM_IMPORT,$(VM_RAW_NAME),$(QEMU_DISK_RAW),raw,--import)
start-vm-raw-boot: define-vm-raw-boot ; @echo "Starting VM: $(VM_RAW_NAME)..."; $(SUDO) virsh start $(VM_RAW_NAME)
console-vm-raw-boot: ; @echo "Console for $(VM_RAW_NAME)..."; $(SUDO) virsh console $(VM_RAW_NAME)
stop-vm-raw-boot: ; @echo "Stopping VM: $(VM_RAW_NAME)..."; -$(SUDO) virsh shutdown $(VM_RAW_NAME) --timeout 10 || $(SUDO) virsh destroy $(VM_RAW_NAME)
destroy-vm-raw-boot: stop-vm-raw-boot ; @echo "Undefining VM: $(VM_RAW_NAME)..."; -$(SUDO) virsh undefine $(VM_RAW_NAME) > /dev/null 2>&1

# --- Main Targets to Create and Run VMs ---
vm: vm-qcow # Default 'make vm'

vm-qcow: start-vm-qcow ; @echo "To connect: make console-vm-qcow"; $(SUDO) virsh console $(VM_QCOW_NAME)
vm-iso: start-vm-iso-installer ; @echo "To connect: make console-vm-iso-installer"; $(SUDO) virsh console $(VM_ISO_NAME)
vm-raw: start-vm-raw-boot ; @echo "To connect: make console-vm-raw-boot"; $(SUDO) virsh console $(VM_RAW_NAME)

# Cleanup all defined VMs
destroy-all-vms:
	@echo "Destroying and undefining all VMs..."
	-$(SUDO) virsh destroy $(VM_QCOW_NAME) > /dev/null 2>&1 || true
	-$(SUDO) virsh undefine $(VM_QCOW_NAME) > /dev/null 2>&1 || true
	-$(SUDO) virsh destroy $(VM_ISO_NAME) > /dev/null 2>&1 || true
	-$(SUDO) virsh undefine $(VM_ISO_NAME) > /dev/null 2>&1 || true
	-$(SUDO) virsh destroy $(VM_RAW_NAME) > /dev/null 2>&1 || true
	-$(SUDO) virsh undefine $(VM_RAW_NAME) > /dev/null 2>&1 || true
	@echo "All defined VMs processed."

.PHONY: clean image bib_image iso qcow2 build-image-raw ifimage \
    ensure_iso_install_target_disk selinux-allow-libvirt-homedirs \
    define-vm-qcow start-vm-qcow console-vm-qcow stop-vm-qcow destroy-vm-qcow \
    define-vm-iso-installer start-vm-iso-installer console-vm-iso-installer stop-vm-iso-installer destroy-vm-iso-installer \
    define-vm-raw-boot start-vm-raw-boot console-vm-raw-boot stop-vm-raw-boot destroy-vm-raw-boot \
    vm vm-qcow vm-iso vm-raw destroy-all-vms