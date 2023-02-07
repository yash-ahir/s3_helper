import 'dart:io';
import 'package:path/path.dart';
import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:xml/xml.dart';

class S3Helper {
  final String accessKeyId;
  final String accessKeySecret;
  final String bucketUrl;
  final String region;

  late final AWSSigV4Signer _signer;
  late final AWSCredentialScope _scope;
  late final ServiceConfiguration _serviceConfiguration;

  S3Helper({
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.bucketUrl,
    this.region = "ap-south-1",
  }) {
    _signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(
        AWSCredentials(accessKeyId, accessKeySecret),
      ),
    );

    _scope = AWSCredentialScope(region: region, service: AWSService.s3);

    _serviceConfiguration = const ServiceConfiguration();
  }

  Future<void> upload(File file) async {
    final contents = file.openRead();
    String key = '/${basename(file.path)}';

    final request = AWSStreamedHttpRequest(
      method: AWSHttpMethod.put,
      uri: Uri(host: bucketUrl, path: key, scheme: "https"),
      body: contents,
      headers: {
        AWSHeaders.host: bucketUrl,
      },
    );

    final signedRequest = await _signer.sign(
      request,
      credentialScope: _scope,
      serviceConfiguration: _serviceConfiguration,
    );

    final response = signedRequest.send();
    final statusCode = (await response.response).statusCode;

    if (statusCode != 200) {
      throw Exception("Could not upload file: $statusCode");
    }
  }

  Future<List<String>> listObjects() async {
    final request = AWSStreamedHttpRequest(
      method: AWSHttpMethod.get,
      uri: Uri(host: bucketUrl, path: "/", scheme: "https"),
      headers: {
        AWSHeaders.host: bucketUrl,
        AWSHeaders.accept: "application/xml"
      },
    );

    final signedRequest = await _signer.sign(
      request,
      credentialScope: _scope,
      serviceConfiguration: _serviceConfiguration,
    );

    final response = signedRequest.send();
    final statusCode = (await response.response).statusCode;
    final bodyXml = await (await response.response).decodeBody();
    final data = XmlDocument.parse(bodyXml)
        .document!
        .rootElement
        .findAllElements("Key")
        .map((e) => e.text)
        .toList();

    if (statusCode != 200) {
      throw Exception("Could not list bucket contents: $statusCode");
    }

    return data;
  }

  Future<File> download(String name) async {
    final request = AWSStreamedHttpRequest(
      method: AWSHttpMethod.get,
      uri: Uri(host: bucketUrl, path: "/$name", scheme: "https"),
      headers: {
        AWSHeaders.host: bucketUrl,
      },
    );

    final signedRequest = await _signer.sign(
      request,
      credentialScope: _scope,
      serviceConfiguration: _serviceConfiguration,
    );

    final response = signedRequest.send();
    final statusCode = (await response.response).statusCode;

    final file = File("${Directory.current.path}/temp/$name")
        .create(recursive: true)
        .then(
          (file) async => file.writeAsBytes(
        await (await response.response).bodyBytes,
      ),
    );

    if (statusCode != 200) {
      throw Exception("Could not download file: $statusCode");
    }

    return file;
  }

  Future<void> delete(String name) async {
    String key = '/$name';

    final request = AWSStreamedHttpRequest(
      method: AWSHttpMethod.delete,
      uri: Uri(host: bucketUrl, path: key, scheme: "https"),
      headers: {
        AWSHeaders.host: bucketUrl,
        AWSHeaders.contentType: 'text/plain',
      },
    );

    final signedRequest = await _signer.sign(
      request,
      credentialScope: _scope,
      serviceConfiguration: _serviceConfiguration,
    );

    final response = signedRequest.send();
    final statusCode = (await response.response).statusCode;

    if (statusCode != 204) {
      throw Exception("Could not delete file: $statusCode");
    }
  }
}
