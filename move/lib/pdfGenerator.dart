import 'dart:io';

import 'package:flutter/services.dart';

import 'package:path_provider/path_provider.dart';

import 'package:pdf/pdf.dart';

import 'package:pdf/widgets.dart' as pw;

import 'package:open_file/open_file.dart';

/// Asynchronously generates a simple PDF document with provided content

/// and saves it to temporary storage. Then opens the PDF file on the device.

Future<void> createSimplePDF(

    String title1, // Title for the first section

    String title2, // Title for the second section

    String body1,  // Body text for the first section

    String body2,  // Body text for the second section

    ) async {

  // Create a PDF document

  final pdf = pw.Document();

  // Write content on the PDF

  pdf.addPage(

//The pw.MultiPage() function in the PDF library is like a smart assistant that automatically handles long content in your PDF by creating multiple pages, making it easy to organize and present your information neatly.

    pw.MultiPage(

      pageFormat: PdfPageFormat.a4,

      margin: pw.EdgeInsets.all(32),

      build: (pw.Context context) {

        return <pw.Widget>[

          pw.Header(

            level: 0,

            child: pw.Row(

              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,

              children: <pw.Widget>[

                pw.Text('simple PDF', textScaleFactor: 2), // Title of the PDF

              ],

            ),

          ),

          pw.Header(level: 1, text: '$title1'), // Header for the first section

          // Write All the paragraphs for the first section

          pw.Paragraph(

            text: '$body1', // Body text for the first section

          ),

          pw.Header(level: 1, text: '$title2'), // Header for the second section

          pw.Paragraph(

            text: '$body2', // Body text for the second section

          ),

          pw.Padding(padding: const pw.EdgeInsets.all(10)),

          pw.Table.fromTextArray( // Creating a table

            context: context,

            data: const <List<String>>[ // Data for the table

              <String>['Year', 'Sample'], // Table headers

              <String>['2004', 'GFG1'],    // Row 1

              <String>['2005', 'GFG2'],    // Row 2

              <String>['2006', 'GFG3'],    // Row 3

              <String>['2007', 'GFG4'],    // Row 4

            ],

          ),

        ];

      },

    ),

  );

  // Get the temporary directory

  final output = await getTemporaryDirectory();

  final file = File('${output.path}/simplePdf.pdf');

  // Save the PDF to temporary storage

  await file.writeAsBytes(await pdf.save());

  // Open the PDF file on the device

  OpenFile.open(file.path);

}