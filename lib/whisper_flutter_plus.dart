import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:easy_dart_logger/easy_dart_logger.dart';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';
import 'package:whisper_flutter_plus/download_model.dart';
import 'package:whisper_flutter_plus/models/requests/transcribe_request.dart';
import 'package:whisper_flutter_plus/models/requests/transcribe_request_dto.dart';
import 'package:whisper_flutter_plus/models/requests/version_request.dart';
import 'package:whisper_flutter_plus/models/responses/whisper_transcribe_response.dart';
import 'package:whisper_flutter_plus/models/responses/whisper_version_response.dart';
import 'package:whisper_flutter_plus/models/whisper_dto.dart';

export 'download_model.dart' show WhisperModel;
export 'models/_models.dart';

/// Native request type
typedef WReqNative = Pointer<Utf8> Function(Pointer<Utf8> body);

/// Logger use for whole package
const logger = DartLogger(
  configuration: DartLoggerConfiguration(
    name: 'whisper_flutter_plus',
  ),
);

/// Entry point of whisper_flutter_plus
class Whisper {
  /// [model] is required
  /// [modelDir] is path where downloaded model will be stored.
  /// Default to library directory
  const Whisper({
    required this.model,
    this.modelDir,
  });

  /// model used for transcription
  final WhisperModel model;

  /// override of model storage path
  final String? modelDir;

  DynamicLibrary _openLib() {
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else {
      return DynamicLibrary.open('libwhisper.so');
    }
  }

  Future<String> _getModelDir() async {
    if (modelDir != null) {
      return modelDir!;
    }
    final Directory libraryDirectory = Platform.isAndroid
        ? await getApplicationSupportDirectory()
        : await getLibraryDirectory();
    return libraryDirectory.path;
  }

  Future<void> _initModel() async {
    final String modelDir = await _getModelDir();
    final File modelFile = File(model.getPath(modelDir));
    final bool isModelExist = modelFile.existsSync();
    if (isModelExist) {
      logger.info('Use existing model ${model.modelName}');
      return;
    }

    await downloadModel(
      model: model,
      destinationPath: modelDir,
    );
  }

  Future<Map<String, dynamic>> _request({
    required WhisperRequestDto whisperRequest,
  }) async {
    await _initModel();
    return Isolate.run(
      () async {
        final Pointer<Utf8> data =
            whisperRequest.toRequestString().toNativeUtf8();
        final Pointer<Utf8> res = _openLib()
            .lookupFunction<WReqNative, WReqNative>(
              'request',
            )
            .call(data);

        final Map<String, dynamic> result = json.decode(
          res.toDartString(),
        ) as Map<String, dynamic>;

        malloc.free(data);
        return result;
      },
    );
  }

  /// Transcribe audio file to text
  Future<WhisperTranscribeResponse> transcribe({
    required TranscribeRequest transcribeRequest,
  }) async {
    final req = transcribeRequest.copyWith(audio: transcribeRequest.audio);
    final modelDir = await _getModelDir();
    final result = await _request(
      whisperRequest: TranscribeRequestDto.fromTranscribeRequest(
        req,
        model.getPath(modelDir),
      ),
    );
    if (result['text'] == null) {
      throw Exception(result['message']);
    }
    return WhisperTranscribeResponse.fromJson(result);
  }

  /// Get whisper version
  Future<String?> getVersion() async {
    final Map<String, dynamic> result = await _request(
      whisperRequest: const VersionRequest(),
    );

    final WhisperVersionResponse response = WhisperVersionResponse.fromJson(
      result,
    );
    return response.message;
  }
}
