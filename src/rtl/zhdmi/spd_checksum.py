import argparse
import sys

def checksum(buf):
    return 256 - (sum(buf) & 0xFF)


def main() -> int:
    # set up / validate script args
    parser = argparse.ArgumentParser(prog='SPD Infoframe builder',
                                     description='Convert vendor and product strings into the infoframe packet with checksum',
                                     epilog='Please provide all required arguments to generate infoframe')
    parser.add_argument('--vendor', help='A vendor name', default="")
    parser.add_argument('--product', help='A product description', default="")
    args = parser.parse_args()

    buf = [
        0x83, 0x01, 0x19, # SPD infoframe packet header
        0x00, # checksum
    ]

    vendor = args.vendor
    product = args.product

    for c in vendor[0:8]:
        buf.append(ord(c))

    if (len(vendor) < 8):
       for i in range(0, 8-len(vendor)):
           buf.append(0)

    for c in product[0:16]:
        buf.append(ord(c))

    if (len(product) < 16):
       for i in range(0, 16-len(product)):
           buf.append(0)

    print(f"Vendor: {vendor}")
    print(f"Product: {product}")
    buf[3] = checksum(buf)
    print("")
    print('Buf: [{}]'.format(', '.join(hex(x) for x in buf)))
    print("")
    print("VHDL definition:")
    print("constant spd_infoframe: data_packet_t := (")
    print(", ".join('x"{:02x}"'.format(num) for num in buf))

    print(");")

    return 0

if __name__ == "__main__":
    sys.exit(main())
