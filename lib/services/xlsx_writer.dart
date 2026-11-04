import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Minimal Office Open XML workbook: typed numeric cells, literal text (never
/// formulas), frozen headings, filters and wrapped notes. No external links.
Uint8List writeXlsx(Map<String, List<List<Object?>>> sheets) {
  final zip = Archive();
  void add(String path, String content) =>
      zip.addFile(ArchiveFile.string(path, content));
  String xml(Object? v) => (v?.toString() ?? '')
      .replaceAll(RegExp('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  String column(int n) {
    var s = '';
    for (n++; n > 0; n = (n - 1) ~/ 26) {
      s = String.fromCharCode(65 + (n - 1) % 26) + s;
    }
    return s;
  }

  add(
    '[Content_Types].xml',
    '''<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}</Types>''',
  );
  add(
    '_rels/.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${[for (var i = 0; i < sheets.length; i++) '<sheet name="${xml(sheets.keys.elementAt(i))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}<Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
  );
  add(
    'xl/styles.xml',
    '''<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF204E3C"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf fontId="0" fillId="0" borderId="0" xfId="0"><alignment vertical="top" wrapText="1"/></xf><xf fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''',
  );
  var sheetId = 0;
  for (final rows in sheets.values) {
    final width = rows.isEmpty ? 1 : rows.first.length;
    final out = StringBuffer(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:${column(width - 1)}${rows.isEmpty ? 1 : rows.length}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="$width" width="24" customWidth="1"/></cols><sheetData>',
    );
    for (var r = 0; r < rows.length; r++) {
      out.write(
        '<row r="${r + 1}"${r == 0 ? ' ht="32" customHeight="1"' : ''}>',
      );
      for (var c = 0; c < rows[r].length; c++) {
        final v = rows[r][c];
        if (v == null) continue;
        final ref = '${column(c)}${r + 1}', style = r == 0 ? 1 : 0;
        if (v is num && v.isFinite) {
          out.write('<c r="$ref" s="$style"><v>$v</v></c>');
        } else {
          out.write(
            '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${xml(v)}</t></is></c>',
          );
        }
      }
      out.write('</row>');
    }
    out.write(
      '</sheetData><autoFilter ref="A1:${column(width - 1)}${rows.isEmpty ? 1 : rows.length}"/></worksheet>',
    );
    add('xl/worksheets/sheet${++sheetId}.xml', out.toString());
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

Uint8List writeCsv(List<List<Object?>> rows) {
  String cell(Object? v) {
    if (v == null) return '';
    if (v is num) return '$v';
    var s = v.toString();
    if (RegExp(r'^[\s]*[=+@-]').hasMatch(s) ||
        s.startsWith('\t') ||
        s.startsWith('\r')) {
      s = "'$s";
    }
    return '"${s.replaceAll('"', '""')}"';
  }

  return Uint8List.fromList(
    utf8.encode(
      '\uFEFF${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n',
    ),
  );
}
