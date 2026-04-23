# ba0fde3d-bee7-4307-b97b-17d0d20aff50
# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx

COPY files/system /system_files/
COPY files/scripts /build_files/
COPY *.pub /keys/

# Base Image
FROM quay.io/almalinuxorg/almalinux-bootc:10@sha256:5da1fc71a1379cca79851d2159ac9a886f34e9cfdd7bd04ee5aa7ceecbaa54ea

ARG IMAGE_NAME
ARG IMAGE_REGISTRY
ARG VARIANT
ARG TARGETARCH

RUN --mount=type=tmpfs,dst=/opt \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
