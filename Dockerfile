# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx

COPY files/system /system_files
COPY files/scripts /build_files
COPY *.pub /keys

# Base Image settable as a build argument
ARG BASE=quay.io/almalinuxorg/almalinux-bootc:10-kitten@sha256:196fabb4a5f6020546415b6c2e9309edde7a9993e1e4f7c5634305fc495c4989
FROM $BASE

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
