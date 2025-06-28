import 'package:flutter/material.dart';
import 'model/predictor.dart';

class PredictionPage extends StatefulWidget {
  final List<int> rgb;

  PredictionPage({required this.rgb});

  @override
  _PredictionPageState createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  double? concentration;

  @override
  void initState() {
    super.initState();
    loadModelAndPredict();
  }

  Future<void> loadModelAndPredict() async {
    final predictor = Predictor();
    await predictor.loadModel();
    double result = predictor.predict(widget.rgb);
    setState(() {
      concentration = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Cortisol Result")),
      body: Center(
        child:
            concentration == null
                ? CircularProgressIndicator()
                : Text(
                  "Cortisol Concentration:\n${concentration!.toStringAsFixed(2)} ng/mL",
                  style: TextStyle(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
      ),
    );
  }
}
