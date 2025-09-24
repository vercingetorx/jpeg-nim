import std/math

import common

# Fixed-point conversions -----------------------------------------------------

proc yCbCrToRgb*(y, cb, cr: int): Pixel =
  ## Convert YCbCr triplet (with Y in 0..255, Cb/Cr centred at 128) to RGB.
  let c = y
  let d = cb - 128
  let e = cr - 128
  let r = c + ((91881 * e) shr 16)
  let g = c - ((22554 * d + 46802 * e) shr 16)
  let b = c + ((116130 * d) shr 16)
  (clampToByte(r), clampToByte(g), clampToByte(b))


proc rgbToYCbCr*(r, g, b: uint8): tuple[y, cb, cr: uint8] =
  ## Convert RGB to YCbCr using integer arithmetic.
  let ri = int(r)
  let gi = int(g)
  let bi = int(b)
  let y  = (19595 * ri + 38470 * gi + 7471 * bi + 32768) shr 16
  let cb = ((-11059 * ri - 21709 * gi + 32768 * bi + 8421376) shr 16)
  let cr = ((32768 * ri - 27439 * gi - 5329 * bi + 8421376) shr 16)
  (uint8(clamp(y, 0, 255)), uint8(clamp(cb, 0, 255)), uint8(clamp(cr, 0, 255)))
