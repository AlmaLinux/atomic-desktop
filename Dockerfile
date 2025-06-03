# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx

COPY files/system /system_files
COPY files/scripts /build_files
COPY *.pub /keys

# Base Image
FROM quay.io/almalinuxorg/almalinux-bootc:10@sha256:8d34f96efc6aa8b955dd22d4d4b6d37d95c64b6fa413e3d65d93bf0adde9ca75

ARG IMAGE_NAME
ARG IMAGE_REGISTRY
ARG VARIANT

RUN --mount=type=tmpfs,dst=/opt \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
