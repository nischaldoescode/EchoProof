EchoProof local moderation assets.

Required files for the ONNX spam classifier:

- spam_model.onnx
- spam_model.onnx.data
- vocab.txt
- config.json
- tokenizer_config.json
- tokenizer.json

The ONNX export uses external tensor data, so spam_model.onnx.data must remain
beside spam_model.onnx. The mobile app copies both files into application
support storage before opening the ONNX Runtime session so external data can be
resolved from the filesystem.