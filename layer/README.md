# Pillow layer

The thumbnail Lambda uses a Pillow layer (`arn:aws:lambda:ap-southeast-2:258393933362:layer:pillow:1`). The built files are not committed: they are 29 MB of vendored code.

Rebuild for Python 3.13 on Lambda's platform:

```
mkdir -p python
pip install --platform manylinux2014_x86_64 --only-binary=:all: --target python --python-version 3.13 pillow
zip -r pillow-layer.zip python
aws lambda publish-layer-version --layer-name pillow --zip-file fileb://pillow-layer.zip --compatible-runtimes python3.13
```
