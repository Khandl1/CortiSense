import 'package:tflite_flutter/tflite_flutter.dart';

class Predictor {
  late Interpreter _interpreter;

  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('model.tflite');
  }

  double predict(List<int> rgb) {
    var input = [rgb.map((e) => e.toDouble()).toList()];
    var output = List.filled(1, 0).reshape([1, 1]);

    _interpreter.run(input, output);

    return output[0][0];
  }
}
