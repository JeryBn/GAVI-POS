class Product {
  final String id, name, sku, barcode;
  final int price, wholesale, minimum, cost, stock, low;
  final bool active;
  const Product({required this.id, required this.name, required this.sku,
    this.barcode = '', required this.price, required this.wholesale,
    required this.minimum, required this.cost, required this.stock,
    required this.low, this.active = true});
  factory Product.fromMap(Map<String, dynamic> m) => Product(
    id: m['id'] as String, name: m['name'] as String, sku: m['sku'] as String,
    barcode: m['barcode'] as String? ?? '', price: m['price'] as int,
    wholesale: m['wholesale'] as int, minimum: m['minimum'] as int,
    cost: m['cost'] as int, stock: m['stock'] as int, low: m['low'] as int,
    active: m['active'] == 1 || m['active'] == true);
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'sku': sku,
    'barcode': barcode, 'price': price, 'wholesale': wholesale,
    'minimum': minimum, 'cost': cost, 'stock': stock, 'low': low,
    'active': active ? 1 : 0};
}

class CartLine {
  final Product product;
  int quantity, price;
  CartLine(this.product, {this.quantity = 1, int? price}) : price = price ?? product.price;
  int get total => quantity * price;
  Map<String, dynamic> toMap() => {'product_id': product.id, 'name': product.name,
    'sku': product.sku, 'quantity': quantity, 'price': price, 'total': total};
}

class Operator {
  final String id, name, role;
  final bool canEditPrice, canCredit;
  const Operator(this.id, this.name, this.role,
    {this.canEditPrice = false, this.canCredit = false});
  bool get admin => role == 'admin';
}

String money(int cents) => 'S/ ${(cents / 100).toStringAsFixed(2)}';
int parseMoney(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) {
    throw const FormatException('Ingrese un importe positivo con hasta 2 decimales.');
  }
  final parts = normalized.split('.');
  final result = int.parse(parts[0]) * 100 +
    (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if (result > 1000000000) { throw const FormatException('Importe fuera de rango.'); }
  return result;
}
