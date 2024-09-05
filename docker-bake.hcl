variable "IGNITION_VERSION" {
    default = "8.1.43"
}

variable "BASE_IMAGE_PATH" {
    default = "ghcr.io/username/ignition-docker/ignition"
}

target "default" {
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
        "${BASE_IMAGE_PATH}:${IGNITION_VERSION}"
    ]
}
