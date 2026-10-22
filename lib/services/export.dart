import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';

import '../state/app_state.dart';
import 'db.dart';

/// Cópia de segurança gratuita: guarda todos os dados num ficheiro Excel
/// (uma folha por tipo de dado). Pode ser guardado no Google Drive.
class ExportService {
  static final _d = DateFormat('yyyy-MM-dd HH:mm');

  static Future<String> exportAll(AppState app) async {
    final x = Excel.createExcel();
    final defaultSheet = x.getDefaultSheet();

    TextCellValue t(Object? v) => TextCellValue(v?.toString() ?? '');
    IntCellValue n(int v) => IntCellValue(v);
    DoubleCellValue d(double v) => DoubleCellValue(v);
    void header(Sheet sh, List<String> cols) => sh.appendRow(cols.map(t).toList());

    final prod = x['Produtos'];
    header(prod, ['Nome', 'Categoria', 'Código de barras', 'Unidade', 'Quantidade', 'Caixas fechadas', 'Kg soltos',
      'Mínimo', 'Custo (Kz)', 'Preço (Kz)', 'Validade mais próxima']);
    for (final p in app.products) {
      prod.appendRow([t(p.name), t(p.category), t(p.barcode), t(p.unit), d(p.qty), n(p.boxCount), d(p.looseKg),
        d(p.minQty), n(p.cost), n(p.price),
        t(p.nextExpiry == null ? '' : DateFormat('yyyy-MM-dd').format(p.nextExpiry!))]);
    }

    final boxes = x['Caixas'];
    header(boxes, ['Produto', 'Peso (kg)', 'Validade']);
    for (final p in app.products.where((p) => p.byWeight)) {
      for (final b in p.boxesByExpiry) {
        boxes.appendRow([t(p.name), d(b.kg), t(b.exp == null ? '' : DateFormat('yyyy-MM-dd').format(b.exp!))]);
      }
    }

    final cust = x['Clientes'];
    header(cust, ['Nome', 'Contacto', 'Telefone', 'Email', 'Limite de crédito (Kz)', 'Deve (Kz)', 'Aceita mensagens']);
    for (final c in app.customers) {
      cust.appendRow([t(c.name), t(c.contact), t(c.phone), t(c.email), n(c.creditLimit), n(app.owedBy(c.id)),
        t(c.optIn ? 'Sim' : 'Não')]);
    }

    final sales = x['Vendas'];
    header(sales, ['Nº', 'Data', 'Cliente', 'Pagamento', 'Produto', 'Qtd', 'Unidade', 'Caixa inteira', 'Preço (Kz)',
      'Total linha (Kz)', 'Lucro linha (Kz)']);
    for (final v in await Db.I.allSales()) {
      for (final l in v.lines) {
        sales.appendRow([n(v.number), t(_d.format(v.at)), t(v.customerName), t(v.method), t(l.name), d(l.qty),
          t(l.unit), t(l.box != null ? 'Sim' : ''), n(l.price), n(l.total), n(l.profit)]);
      }
    }

    final bills = x['Contas'];
    header(bills, ['Tipo', 'Cliente / Fornecedor', 'Valor (Kz)', 'Pago (Kz)', 'Falta (Kz)', 'Vence', 'Estado', 'Pago em', 'Nota']);
    for (final b in app.bills) {
      bills.appendRow([t(b.isReceivable ? 'A receber' : 'A pagar'), t(b.party), n(b.amount), n(b.paidAmount),
        n(b.remaining), t(_d.format(b.due)), t(b.isOpen ? 'Pendente' : 'Pago'),
        t(b.paidAt == null ? '' : _d.format(b.paidAt!)), t(b.note)]);
    }

    if (defaultSheet != null) x.delete(defaultSheet);
    final bytes = Uint8List.fromList(x.encode()!);
    final name = 'loja-plus-${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
    await FileSaver.instance.saveFile(name: name, bytes: bytes, ext: 'xlsx', mimeType: MimeType.microsoftExcel);
    return '$name.xlsx';
  }
}
