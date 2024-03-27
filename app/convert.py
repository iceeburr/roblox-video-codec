import base64
import argparse
import os

def encode_file(input_file, output_file):
    with open(input_file, 'rb') as f:
        data = f.read()
    encoded_data = base64.b64encode(data)
    with open(output_file, 'wb') as f:
        f.write(encoded_data)

def decode_file(input_file, output_file):
    with open(input_file, 'rb') as f:
        data = f.read()
    decoded_data = base64.b64decode(data)
    with open(output_file, 'wb') as f:
        f.write(decoded_data)

def main():
    parser = argparse.ArgumentParser(description='Encode/Decode base64 binary data.')
    parser.add_argument('operation', choices=['encode', 'decode'], help='Operation to perform (encode/decode)')
    parser.add_argument('input_file', help='Input file to encode/decode')
    parser.add_argument('-o', '--output', default='output.txt', help='Output file name (default: output.txt)')

    args = parser.parse_args()

    if args.operation == 'encode':
        encode_file(args.input_file, args.output)
    elif args.operation == 'decode':
        decode_file(args.input_file, args.output)

if __name__ == '__main__':
    main()
