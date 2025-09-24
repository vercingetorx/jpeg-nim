import std/math

const
  BlockDim* = 8
  BlockSize* = BlockDim * BlockDim

# Simple RGB pixel helper ----------------------------------------------------

type
  Pixel* = tuple[r, g, b: uint8]

  Image* = object
    width*, height*: int
    data*: seq[uint8]               # row-major RGB, 3 bytes per pixel

  CoeffBlock* = array[BlockSize, int16]
  IntBlock* = array[BlockSize, int32]
  SampleBlock* = array[BlockSize, int16]
  QuantTable* = array[BlockSize, uint16]

  ComponentSpec* = object
    id*: uint8
    hFactor*, vFactor*: uint8       # sampling factors
    quantId*: uint8
    dcTableId*, acTableId*: uint8

  HuffmanTable* = object
    fastBits*: int
    fastMask*: int
    fastLookup*: seq[int16]
    fastCodeLen*: seq[uint8]
    minCode*: array[18, int32]
    maxCode*: array[18, int32]
    valPtr*: array[18, int32]
    values*: seq[int16]
    codes*: array[256, uint16]
    codeLengths*: array[256, uint8]

const
  DefaultFastBits* = 9              # 9 bits offers a good trade-off

# ----------------------------------------------------------------------------

proc clampToByte*(value: int): uint8 {.inline.} =
  ## Clamp an integer to the 0-255 range and cast to byte.
  if value < 0:
    return 0'u8
  if value > 255:
    return 255'u8
  uint8(value)


proc initImage*(width, height: int): Image =
  ## Allocate an RGB image with the given dimensions.
  Image(
    width: width,
    height: height,
    data: newSeq[uint8](width * height * 3)
  )


proc setPixel*(img: var Image, x, y: int, r, g, b: int) {.inline.} =
  ## Write a pixel into the RGB buffer with clamping.
  let idx = (y * img.width + x) * 3
  img.data[idx] = clampToByte(r)
  img.data[idx + 1] = clampToByte(g)
  img.data[idx + 2] = clampToByte(b)


proc getPixel*(img: Image, x, y: int): Pixel {.inline.} =
  let idx = (y * img.width + x) * 3
  (img.data[idx], img.data[idx + 1], img.data[idx + 2])
