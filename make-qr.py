"""Generate the phone-link QR locally; no URL is sent to a third party."""
import sys
import qrcode


def make_qr(url, destination):
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=8, border=4)
    qr.add_data(url)
    qr.make(fit=True)
    qr.make_image(fill_color='black', back_color='white').save(destination)


if __name__ == '__main__':
    make_qr(sys.argv[1], sys.argv[2])
