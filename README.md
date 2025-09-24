# Nim JPEG Codec

This project implements a baseline JPEG encoder and decoder in pure. It supports 8-bit, non-progressive images with 4:2:0 subsampling on the encoder and can read typical baseline JPEG files.

## Features

- JPEG file parser supporting SOI, APP, DQT, DHT, SOF0, SOS, DRI, and EOI markers
- Canonical Huffman table builder and fast decoder with fallback bit-by-bit path
- Integer-friendly color-space conversion between RGB and YCbCr
- 8×8 DCT/IDCT using two-pass cosine transform
- Quantisation/Dequantisation with quality scaling (1–100)
- 4:2:0 chroma subsampling with simple averaging
- Byte-stuffed bitstream reader/writer and restart marker handling
- Command-line tool for decoding to PPM, encoding from PPM, or round-tripping JPEGs

## Building

```
nim c -d:release main.nim
```

## CLI usage

```
# Decode JPEG to binary PPM
./main decode input.jpg output.ppm

# Encode PPM (P6, 8-bit) to JPEG at quality 90
./main encode input.ppm output.jpg 90

# Decode then re-encode JPEG at quality 85
./main roundtrip input.jpg output.jpg 85
```

Only baseline JPEGs are supported (no progressive scans, arithmetic coding, or lossless modes). The encoder writes JFIF-compliant files with default Huffman tables.
