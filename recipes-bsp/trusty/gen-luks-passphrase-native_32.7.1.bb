SUMMARY = "Sample Python application to generate a LUKS passphrase"
DESCRIPTION = "Sample Python application to generate a LUKS passphrase with \
the same algorithms as the luks-srv-app Client Application (CA) and the \
luks-srv Trusted Application (TA)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${WORKDIR}/gen_luks_passphrase.py;beginline=4;endline=23;md5=c0272fe9be2290109a9bb71a49e99c5c"

SRC_URI += "file://gen_luks_passphrase.py"

inherit native python3native

DEPENDS = "python3-cryptography-native"

S = "${WORKDIR}" 

# usage: gen_luks_passphrase.py [-h] -c CONTEXT_STRING [-e ECID] [-k KEY_FILE]
#                               [-u] [-g]
#
# Generates LUKS passphrase by using a key file which indicates a key from EKB.
# The key file includes one user-defined 16-bytes symmetric key.
#
# optional arguments:
#   -h, --help            show this help message and exit
#   -c CONTEXT_STRING, --context-string CONTEXT_STRING
#                         The context string (max 40 byts) for generating
#                         passphrase.
#   -e ECID, --ecid ECID  The ECID (Embedded chip ID) of the chip.
#   -k KEY_FILE, --key-file KEY_FILE
#                         The key (16 bytes) file in hex format.
#   -u, --unique-pass     Generate a unique passphrase.
#   -g, --generic-pass    Generate a generic passphrase.

# Choices are UNIQUE_PASSPHRASE="1" -> -u/--unique-pass
# or UNIQUE_PASSPHRASE="0" -> -g/--generic-pass
UNIQUE_PASSPHRASE ?= "0"
# Similar to the BR_CID, but the first 7 digits are 0 (at least for jetson-agx-xavier)
# -e/--ecid $ECID
ECID ?= ""
# Same as the --user_key for flashing, but without the "0x "
# -k/--key-file $USER_KEY_FOR_EKS
USER_KEY_FOR_EKS ?= ""
# -c/--context-string $DISK_UUID
DISK_UUID ?= ""

do_configure() {
    :
}

do_compile() {
    :
}

do_install() {
    sed -i -e "1s,#!.*python.*,#!${USRBINPATH}/env python3," ${S}/gen_luks_passphrase.py
    install -d ${D}${sbindir}
    install ${S}/gen_luks_passphrase.py ${D}${sbindir}/
}
