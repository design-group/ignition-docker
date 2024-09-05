variable "IGNITION_VERSION" {
    default = "8.1.43"
}

variable "BASE_IMAGE_NAME" {
    default = "ghcr.io/keith-gamble/ignition-docker"
}

target "ignition" {
    context = "."
    args = {
        IGNITION_VERSION = "${IGNITION_VERSION}"
    }
    platforms = [
        "linux/amd64", 
        "linux/arm64", 
        "linux/arm",
    ]
    tags = [
        "${BASE_IMAGE_NAME}:${IGNITION_VERSION}"
    ]
}