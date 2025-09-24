import std/[os, strformat, strutils]

import src/parsing


proc usage() =
  echo "Usage: jpeg <command> [options]\n"
  echo "Commands:"
  echo "  decode <input.jpg> <output.ppm>"
  echo "  encode <input.ppm> <output.jpg> [quality]"
  echo "  roundtrip <input.jpg> <output.jpg> [quality]"


proc writePPM(image: Image, path: string) =
  var file: File
  if not file.open(path, fmWrite):
    raise newException(OSError, &"Cannot open {path} for writing")
  defer: file.close()
  file.write(&"P6\n{image.width} {image.height}\n255\n")
  var buffer = newString(image.data.len)
  for i in 0 ..< image.data.len:
    buffer[i] = char(image.data[i])
  file.write(buffer)


proc readPPM(path: string): Image =
  let raw = readFile(path)
  var idx = 0
  proc nextToken(): string =
    while true:
      while idx < raw.len and raw[idx] in {' ', '\n', '\r', '\t'}:
        inc idx
      if idx < raw.len and raw[idx] == '#':
        while idx < raw.len and raw[idx] != '\n':
          inc idx
        continue
      break
    var start = idx
    while idx < raw.len and raw[idx] notin {' ', '\n', '\r', '\t'}:
      inc idx
    raw[start ..< idx]

  if nextToken() != "P6":
    raise newException(ValueError, "Only binary P6 PPM supported")
  let width = nextToken().parseInt
  let height = nextToken().parseInt
  let maxVal = nextToken().parseInt
  if maxVal != 255:
    raise newException(ValueError, "Only max value 255 supported")
  while idx < raw.len and raw[idx] in {' ', '\n', '\r', '\t'}:
    inc idx
  var img = initImage(width, height)
  let expected = width * height * 3
  if idx + expected > raw.len:
    raise newException(ValueError, "PPM file truncated")
  for i in 0 ..< expected:
    img.data[i] = uint8(ord(raw[idx + i]))
  img


when isMainModule:
  if paramCount() < 3:
    usage()
  else:
    let cmd = paramStr(1)
    case cmd
    of "decode":
      let input = paramStr(2)
      let output = paramStr(3)
      let image = loadJpeg(input)
      writePPM(image, output)
    of "encode":
      let input = paramStr(2)
      let output = paramStr(3)
      let quality = if paramCount() >= 4: paramStr(4).parseInt else: 90
      let image = readPPM(input)
      let jpegData = encodeJpeg(image, quality)
      var dataStr = newString(jpegData.len)
      for i in 0 ..< jpegData.len:
        dataStr[i] = char(jpegData[i])
      writeFile(output, dataStr)
    of "roundtrip":
      let input = paramStr(2)
      let output = paramStr(3)
      let quality = if paramCount() >= 4: paramStr(4).parseInt else: 90
      let image = loadJpeg(input)
      let jpegData = encodeJpeg(image, quality)
      var dataStr = newString(jpegData.len)
      for i in 0 ..< jpegData.len:
        dataStr[i] = char(jpegData[i])
      writeFile(output, dataStr)
    else:
      usage()
