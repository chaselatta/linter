// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:linter/src/analyzer.dart';

const alwaysFalse = 'Always false because length is always greater or equal 0.';

const alwaysTrue = 'Always true because length is always greater or equal 0.';

const useIsEmpty = 'Use isEmpty instead of length';
const useIsNotEmpty = 'Use isNotEmpty instead of length';
const _desc = r'Use `isEmpty` for Iterables and Maps.';
const _details = r'''

**DON'T** use `length` to see if a collection is empty.

The `Iterable` contract does not require that a collection know its length or be
able to provide it in constant time.  Calling `length` just to see if the
collection contains anything can be painfully slow.

Instead, there are faster and more readable getters: `isEmpty` and
`isNotEmpty`.  Use the one that doesn't require you to negate the result.

**GOOD:**
```
if (lunchBox.isEmpty) return 'so hungry...';
if (words.isNotEmpty) return words.join(' ');
```

**BAD:**
```
if (lunchBox.length == 0) return 'so hungry...';
if (words.length != 0) return words.join(' ');
```

''';

class PreferIsEmpty extends LintRule implements NodeLintRule {
  PreferIsEmpty()
      : super(
            name: 'prefer_is_empty',
            description: _desc,
            details: _details,
            group: Group.style);

  @override
  void registerNodeProcessors(NodeLintRegistry registry) {
    final visitor = new _Visitor(this);
    registry.addSimpleIdentifier(this, visitor);
  }

  void reportLintWithDescription(AstNode node, String description) {
    if (node != null) {
      reporter.reportErrorForNode(new _LintCode(name, description), node, []);
    }
  }
}

class _LintCode extends LintCode {
  static final registry = <String, LintCode>{};

  factory _LintCode(String name, String message) => registry.putIfAbsent(
      name + message, () => new _LintCode._(name, message));

  _LintCode._(String name, String message) : super(name, message);
}

class _Visitor extends SimpleAstVisitor<void> {
  final PreferIsEmpty rule;

  _Visitor(this.rule);

  @override
  void visitSimpleIdentifier(SimpleIdentifier identifier) {
    // Should be "length".
    Element propertyElement = identifier.bestElement;
    if (propertyElement?.name != 'length') {
      return;
    }

    AstNode lengthAccess;
    InterfaceType type;

    AstNode parent = identifier.parent;
    if (parent is PropertyAccess && identifier == parent.propertyName) {
      lengthAccess = parent;
      if (parent.target?.bestType is! InterfaceType) {
        return;
      }
      type = parent.target?.bestType;
    } else if (parent is PrefixedIdentifier &&
        identifier == parent.identifier) {
      lengthAccess = parent;
      if (parent.prefix.bestType is! InterfaceType) {
        return;
      }
      type = parent.prefix.bestType;
    } else {
      return;
    }

    // Should be subtype of Iterable, Map or String.
    AnalysisContext context = propertyElement.context;
    TypeProvider typeProvider = context.typeProvider;
    TypeSystem typeSystem = context.typeSystem;

    if (typeSystem.mostSpecificTypeArgument(type, typeProvider.iterableType) ==
            null &&
        typeSystem.mostSpecificTypeArgument(type, typeProvider.mapType) ==
            null &&
        !type.element.type.isSubtypeOf(typeProvider.stringType)) {
      return;
    }

    AstNode search = lengthAccess;
    while (
        search != null && search is Expression && search is! BinaryExpression) {
      search = search.parent;
    }

    if (search is! BinaryExpression) {
      return;
    }
    BinaryExpression binaryExpression = search;

    Token operator = binaryExpression.operator;

    // Comparing constants with length.
    int value = _getIntValue(binaryExpression.rightOperand);

    if (value != null) {
      // Constant is on right side of comparison operator.
      if (value == 0) {
        if (operator.type == TokenType.EQ_EQ ||
            operator.type == TokenType.LT_EQ) {
          rule.reportLintWithDescription(binaryExpression, useIsEmpty);
        } else if (operator.type == TokenType.GT ||
            operator.type == TokenType.BANG_EQ) {
          rule.reportLintWithDescription(binaryExpression, useIsNotEmpty);
        } else if (operator.type == TokenType.LT) {
          rule.reportLintWithDescription(binaryExpression, alwaysFalse);
        } else if (operator.type == TokenType.GT_EQ) {
          rule.reportLintWithDescription(binaryExpression, alwaysTrue);
        }
      } else if (value == 1) {
        // 'length >= 1' is same as 'isNotEmpty',
        // and 'length < 1' is same as 'isEmpty'
        if (operator.type == TokenType.GT_EQ) {
          rule.reportLintWithDescription(binaryExpression, useIsNotEmpty);
        } else if (operator.type == TokenType.LT) {
          rule.reportLintWithDescription(binaryExpression, useIsEmpty);
        }
      } else if (value < 0) {
        // 'length' is always >= 0, so comparing with negative makes no sense.
        if (operator.type == TokenType.EQ_EQ ||
            operator.type == TokenType.LT_EQ ||
            operator.type == TokenType.LT) {
          rule.reportLintWithDescription(binaryExpression, alwaysFalse);
        } else if (operator.type == TokenType.BANG_EQ ||
            operator.type == TokenType.GT_EQ ||
            operator.type == TokenType.GT) {
          rule.reportLintWithDescription(binaryExpression, alwaysTrue);
        }
      }
      return;
    }

    value = _getIntValue(binaryExpression.leftOperand);

    // ignore: invariant_booleans
    if (value != null) {
      // Constant is on left side of comparison operator.
      if (value == 0) {
        if (operator.type == TokenType.EQ_EQ ||
            operator.type == TokenType.GT_EQ) {
          rule.reportLintWithDescription(binaryExpression, useIsEmpty);
        } else if (operator.type == TokenType.LT ||
            operator.type == TokenType.BANG_EQ) {
          rule.reportLintWithDescription(binaryExpression, useIsNotEmpty);
        } else if (operator.type == TokenType.GT) {
          rule.reportLintWithDescription(binaryExpression, alwaysFalse);
        } else if (operator.type == TokenType.LT_EQ) {
          rule.reportLintWithDescription(binaryExpression, alwaysTrue);
        }
      } else if (value == 1) {
        // '1 <= length' is same as 'isNotEmpty',
        // and '1 > length' is same as 'isEmpty'
        if (operator.type == TokenType.LT_EQ) {
          rule.reportLintWithDescription(binaryExpression, useIsNotEmpty);
        } else if (operator.type == TokenType.GT) {
          rule.reportLintWithDescription(binaryExpression, useIsEmpty);
        }
      } else if (value < 0) {
        // 'length' is always >= 0, so comparing with negative makes no sense.
        if (operator.type == TokenType.EQ_EQ ||
            operator.type == TokenType.GT_EQ ||
            operator.type == TokenType.GT) {
          rule.reportLintWithDescription(binaryExpression, alwaysFalse);
        } else if (operator.type == TokenType.BANG_EQ ||
            operator.type == TokenType.LT_EQ ||
            operator.type == TokenType.LT) {
          rule.reportLintWithDescription(binaryExpression, alwaysTrue);
        }
      }
    }
  }

  /// Returns the value of an [IntegerLiteral] or [PrefixExpression] with a
  /// minus and then an [IntegerLiteral]. For anything else, returns `null`.
  int _getIntValue(Expression expressions) {
    if (expressions is IntegerLiteral) {
      return expressions.value;
    } else if (expressions is PrefixExpression) {
      var operand = expressions.operand;
      if (expressions.operator.type == TokenType.MINUS &&
          operand is IntegerLiteral) {
        return -operand.value;
      }
    }
    // ignore: avoid_returning_null
    return null;
  }
}
