# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx

COPY files/system /system_files
COPY files/scripts /build_files
COPY *.pub /keys

# Base Image
FROM quay.io/almalinuxorg/almalinux-bootc:10.0

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
