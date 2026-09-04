#!/usr/bin/env python3
import sys
import argparse
import re
import subprocess
from enum import Enum
from pathlib import Path
from typing import List
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from liblk.image import LkImage
from liblk.structures.certificate import Certificate
from pyasn1.codec.der.encoder import encode as der_encode
from pyasn1.type.univ import BitString


def _write_bytes(path: str, data: bytes) -> None:
    try:
        with open(path, "wb") as f:
            f.write(data)
    except PermissionError:
        print(f"[-] Permission denied writing '{path}'.")
        print("    If a previous run used sudo, this file may be owned by root.")
        print(f"    Fix with: sudo chown $USER '{path}'  (or delete the file and re-run)")
        sys.exit(1)


class CertBypassMode(str, Enum):
    WRAP = 'wrap'
    OVERRIDE = 'override'


def build_bypass_cert2_wrap(
    original_cert2: bytes, header_hash: bytes, image_hash: bytes
) -> bytes:
    cert = Certificate.from_bytes(original_cert2)
    verified_copy = der_encode(BitString(hexValue=bytes(original_cert2).hex()))
    forged_copy = cert.encode_with_hashes(header_hash, image_hash)
    return verified_copy + forged_copy


def build_bypass_cert2_override(
    original_cert2: bytes, header_hash: bytes, image_hash: bytes
) -> bytes:
    cert = Certificate.from_bytes(original_cert2)
    override = cert.build_hash_override_block(header_hash, image_hash)
    return override + bytes(original_cert2)


_CERT_BUILDERS = {
    CertBypassMode.WRAP: build_bypass_cert2_wrap,
    CertBypassMode.OVERRIDE: build_bypass_cert2_override,
}


def apply_cert_bypass(
    image: LkImage, mode: CertBypassMode = CertBypassMode.OVERRIDE
) -> List[str]:
    build = _CERT_BUILDERS[CertBypassMode(mode)]
    signed = []

    for name, partition in image.partitions.items():
        if partition.cert2 is None:
            continue

        status = partition.matches_cert2()

        if status is None:
            print(f"[-] Partition '{name}' cert2 could not be parsed. Skipping cert bypass.")
            continue

        if status:
            continue

        header_hash, image_hash = partition.compute_hashes()
        original = bytes(partition.cert2.data)
        partition.cert2.data = build(original, header_hash, image_hash)

        print(
            f"[+] Cert bypass applied to partition '{name}' "
            f"({CertBypassMode(mode).value}, cert2 {len(original)} -> {len(partition.cert2.data)} bytes)"
        )
        signed.append(name)

    if signed:
        image._rebuild_contents()

    return signed


def get_keys():
    private_key_path = Path("private.pem")
    public_key_path = Path("public.pem")

    if private_key_path.exists() and public_key_path.exists():
        with private_key_path.open("rb") as f:
            private_key = serialization.load_pem_private_key(
                f.read(),
                password=None
            )

        with public_key_path.open("rb") as f:
            public_key = serialization.load_pem_public_key(f.read())

        print("[+] Existing keys found. Using private.pem and public.pem")
        return private_key, public_key

    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048
    )

    _write_bytes(str(private_key_path), private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption()
    ))

    public_key = private_key.public_key()
    _write_bytes(str(public_key_path), public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    ))

    print("[+] New keys have been generated and saved into private.pem и public.pem")
    return private_key, public_key


def patch_img(
    img_path: str, output_path: str = None, use_wrap: bool = False
):
    if output_path is None:
        img = Path(img_path)
        output_path = str(img.with_name(f"{img.stem}_patched{img.suffix}"))

    _, new_pub_key = get_keys()
    new_n_bytes = new_pub_key.public_numbers().n.to_bytes(256, byteorder='big')

    try:
        with open("xiaomi.pem", "rb") as f:
            old_pub_key = serialization.load_pem_public_key(f.read())
    except FileNotFoundError:
        print("[-] 'xiaomi.pem' file not found.")
        sys.exit(1)

    old_n_bytes = old_pub_key.public_numbers().n.to_bytes(256, byteorder='big')
    try:
        with open(img_path, "rb") as f:
            data = f.read()
    except FileNotFoundError:
        print(f"[-] '{img_path}' file not found.")
        sys.exit(1)

    pos = data.find(old_n_bytes)

    if pos == -1:
        print("[-] Error: Xiaomi's public key modulus not found in LK image. Nothing to patch.")
        sys.exit(1)

    print(f"[+] Original key modulus found at offset 0x{pos:X}")

    patched_data = data[:pos] + new_n_bytes + data[pos + len(new_n_bytes):]

    print(f"[+] Public key patched successfully")

    try:
        image = LkImage(patched_data)
        cert_bypass_mode = CertBypassMode.WRAP if use_wrap else CertBypassMode.OVERRIDE
        print(f"[+] Selected cert bypass mode: {cert_bypass_mode.value}")
        signed = apply_cert_bypass(image, cert_bypass_mode)
        if signed:
            patched_data = bytes(image.contents)
            print(f"[+] Cert bypass completed for: {', '.join(signed)}")
        else:
            print("[+] Cert bypass was not needed")
    except Exception as exc:
        print(f"[-] Failed to apply cert bypass: {exc}")
        sys.exit(1)

    _write_bytes(output_path, patched_data)

    print(f"[+] All done! Lk saved to: {output_path}")


def encode(token: bytes) -> bytes:
    if len(token) > 253:
        raise ValueError("Bad token")
    ps = b'\xff' * (256 - len(token) - 3)
    return b'\x00\x01' + ps + b'\x00' + token


def sign_token(token: bytes):
    if isinstance(token, str):
        token = token.encode()

    try:
        with open("private.pem", "rb") as f:
            priv = serialization.load_pem_private_key(
                f.read(),
                password=None
            )
    except FileNotFoundError:
        print("[-] private.pem file not found. Please run 'patch' command first.")
        sys.exit(1)

    numbers = priv.private_numbers()
    n = numbers.public_numbers.n
    d = numbers.d

    em = encode(token)
    m = int.from_bytes(em, "big")
    s = pow(m, d, n)
    signature = s.to_bytes(256, "big")

    _write_bytes("signature.bin", signature)

    print("[+] The token signature was successfully generated and saved to 'signature.bin'")


def run_fastboot(*args: str) -> subprocess.CompletedProcess:
    command = ["fastboot", *args]

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False
        )
    except FileNotFoundError:
        print("[-] fastboot binary not found. Put it in the program folder or add it to PATH.")
        sys.exit(1)
    except OSError as exc:
        print(f"[-] Failed to run fastboot: {exc}")
        sys.exit(1)

    if result.returncode != 0:
        error_text = (result.stderr or result.stdout).strip()
        if error_text:
            print(f"[-] Fastboot command failed: {' '.join(args)}")
            print(error_text)
        else:
            print(f"[-] Fastboot command failed: {' '.join(args)}")
        sys.exit(1)

    return result


def extract_token(output: str) -> str:
    token_lines = []

    for line in output.splitlines():
        match = re.match(r"^\(bootloader\)\s+token:\s*(.+)$", line.strip(), re.IGNORECASE)
        if match:
            token_lines.append(match.group(1).strip())

    if token_lines:
        return "".join(token_lines)

    return ""


def unlock_device(dry_run: bool = False):
    print("[+] Looking for fastboot devices...")
    devices_result = run_fastboot("devices")
    devices = [line.strip().split(" ")[0] for line in devices_result.stdout.splitlines() if line.strip()]

    if not devices:
        print("[-] No fastboot devices found.")
        sys.exit(1)

    print(f"[+] Device found: {devices[0]}")

    print("[+] Reading unlock token...")
    token_result = run_fastboot("oem", "get_token")
    token_output = (token_result.stdout or "") + (token_result.stderr or "")
    token = extract_token(token_output)

    if not token:
        print("[-] Failed to extract token from fastboot output.")
        sys.exit(1)

    print(f"[+] Token received: {token}")

    print("[+] Signing token...")
    sign_token(token)

    if dry_run:
        print("[+] Dry run enabled. Skipping fastboot stage and fastboot oem unlock")
        return

    print("[+] Uploading signature.bin to device...")
    run_fastboot("stage", "signature.bin")

    print("[+] Sending unlock command...")
    run_fastboot("oem", "unlock")

    print("[+] Device unlock command completed successfully")


def main():
    parser = argparse.ArgumentParser(description="Unlocking Xiaomi mtk bootloader by patching the public key.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    patch_parser = subparsers.add_parser("patch", help="Patch lk.img")
    patch_parser.add_argument("img", help="lk.img file path")
    patch_parser.add_argument("-o", "--output", help="Output file path", default=None)
    patch_parser.add_argument("--wrap", action="store_true", help="Use wrap mode for cert bypass")

    sign_parser = subparsers.add_parser("sign", help="Sign the token")
    sign_parser.add_argument("token", help="Token string")

    unlock_parser = subparsers.add_parser("unlock", help="Unlock patched device automatically")
    unlock_parser.add_argument("--dry-run", action="store_true", help="Read and sign token, but skip stage and unlock")

    args = parser.parse_args()

    print("[*] LK-Unlock v1.0 by @georgiynesterov")

    if args.command == "patch":
        patch_img(args.img, args.output, args.wrap)
    elif args.command == "sign":
        sign_token(args.token)
    elif args.command == "unlock":
        unlock_device(args.dry_run)


if __name__ == "__main__":
    main()
