import qrcode
import qrcode.image.svg

img = qrcode.make('stevekc.com', image_factory=qrcode.image.svg.SvgImage)

with open('qr.svg', 'wb') as qr:
    img.save(qr)