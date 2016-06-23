// Licensed to Cloudera, Inc. under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  Cloudera, Inc. licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

%lex
%options case-insensitive
%s hive impala
%x hdfs stringValue
%%

[ \t\n]                             { /* skip whitespace */ }
'--'.*                              { /* skip comments */ }
[/][*][^*]*[*]+([^/*][^*]*[*]+)*[/] { /* skip comments */ }

'|CURSOR|'                          { parser.yy.cursorFound = true; return 'CURSOR'; }
'|PARTIAL_CURSOR|'                  { parser.yy.cursorFound = true; return 'PARTIAL_CURSOR'; }

'AND'                               { return 'AND'; }
'BIGINT'                            { return 'BIGINT'; }
'BOOLEAN'                           { return 'BOOLEAN'; }
'BY'                                { return 'BY'; }
'CHAR'                              { return 'CHAR'; }
'CREATE'                            { return 'CREATE'; }
'DECIMAL'                           { return 'DECIMAL'; }
'DOUBLE'                            { return 'DOUBLE'; }
'FLOAT'                             { return 'FLOAT'; }
'FROM'                              { return 'FROM'; }
'GROUP'                             { return 'GROUP'; }
'INT'                               { return 'INT'; }
'INTO'                              { return 'INTO'; }
'IS'                                { return 'IS'; }
'JOIN'                              { return 'JOIN'; }
'NOT'                               { return 'NOT'; }
'ON'                                { return 'ON'; }
'OR'                                { return 'OR'; }
'ORDER'                             { return 'ORDER'; }
'SELECT'                            { determineCase(yytext); return 'SELECT'; }
'SET'                               { return 'SET'; }
'SMALLINT'                          { return 'SMALLINT'; }
'STRING'                            { return 'STRING'; }
'TABLE'                             { return 'TABLE'; }
'TIMESTAMP'                         { return 'TIMESTAMP'; }
'TINYINT'                           { return 'TINYINT'; }
'UPDATE'                            { determineCase(yytext); return 'UPDATE'; }
'USE'                               { determineCase(yytext); return 'USE'; }
'VARCHAR'                           { return 'VARCHAR'; }
'VIEW'                              { return 'VIEW'; }
'WHERE'                             { return 'WHERE'; }

<hive>'AS'                          { return '<hive>AS'; }
<hive>'BINARY'                      { return '<hive>BINARY'; }
<hive>'DATA'                        { return '<hive>DATA'; }
<hive>'DATE'                        { return '<hive>DATE'; }
<hive>'EXTERNAL'                    { return '<hive>EXTERNAL'; }
<hive>'INPATH'                      { this.begin('hdfs'); return '<hive>INPATH'; }
<hive>'LATERAL'                     { return '<hive>LATERAL'; }
<hive>'LOAD'                        { return '<hive>LOAD'; }
<hive>'LOCATION'                    { this.begin('hdfs'); return '<hive>LOCATION'; }

<hive>'explode'                     { return '<hive>explode'; }
<hive>'posexplode'                     { return '<hive>posexplode'; }

<hive>[.]                           { return '<hive>.'; }

<impala>'DATA'                      { return '<impala>DATA'; }
<impala>'EXTERNAL'                  { return '<impala>EXTERNAL'; }
<impala>'INPATH'                    { this.begin('hdfs'); return '<impala>INPATH'; }
<impala>'LOAD'                      { return '<impala>LOAD'; }
<impala>'LOCATION'                  { this.begin('hdfs'); return '<impala>LOCATION'; }

<impala>[.]                         { return '<impala>.'; }

[0-9]+                              { return 'UNSIGNED_INTEGER'; }
[A-Za-z][A-Za-z0-9_]*               { return 'REGULAR_IDENTIFIER'; }

<hdfs>'|CURSOR|'                    { parser.yy.cursorFound = true; return 'CURSOR'; }
<hdfs>'|PARTIAL_CURSOR|'            { parser.yy.cursorFound = true; return 'PARTIAL_CURSOR'; }
<hdfs>\s+[']                        { return 'HDFS_START_QUOTE'; }
<hdfs>[^'|]+                        { return 'HDFS_PATH'; }
<hdfs>[']                           { this.popState(); return 'HDFS_END_QUOTE'; }
<hdfs><<EOF>>                       { return 'EOF'; }

<stringValue>[^']+                  { return 'VALUE'; }
<stringValue>\'                     { this.popState(); return 'SINGLE_QUOTE'; }

[-+&~|^/%*(),.;!]                   { return yytext; }
[=<>]                               { return yytext; }

\[                                  { return '['; }
\]                                  { return ']'; }

\'                                  { this.begin('stringValue'); return 'SINGLE_QUOTE'; }
\"                                  { return 'DOUBLE_QUOTE'; }

<<EOF>>                             { return 'EOF'; }

/lex

%start Sql

%%

AnyCursor
 : 'CURSOR'
 | 'PARTIAL_CURSOR'
 ;

NoOrPartialRegularIdentifier
 : 'REGULAR_IDENTIFIER' 'PARTIAL_CURSOR'
 | 'CURSOR'
 ;

InitResults
 : /* empty */
   {
     parser.yy.result = {};
     parser.yy.cursorFound = false;

     // TODO: Move these below before token or use $$ instead
     delete parser.yy.latestTablePrimaries;
     delete parser.yy.identifierChain;
     delete parser.yy.derivedColumnChain;
     delete parser.yy.currentViews;
     delete parser.yy.keepColumns;

     parser.parseError = function (message, error) {
       if (typeof parser.yy.result.suggestColumns !== 'undefined') {
         linkTablePrimaries();
       }
       prioritizeSuggestions();
       parser.yy.result.error = error;
       return message;
     }
   }
 ;

Sql
 : InitResults SqlStatements ';' EOF
   {
     prioritizeSuggestions();
     return parser.yy.result;
   }
 | InitResults SqlStatements EOF
   {
     prioritizeSuggestions();
     return parser.yy.result;
   }
 ;

SqlStatements
 : SqlStatement
 | SqlStatements ';' SqlStatement
 ;

SqlStatement
 : UseStatement
 | DataManipulation
 | TableDefinition
 | QueryExpression
 | 'REGULAR_IDENTIFIER' 'PARTIAL_CURSOR' 'REGULAR_IDENTIFIER'
 | 'REGULAR_IDENTIFIER' 'PARTIAL_CURSOR'
   {
     suggestDdlAndDmlKeywords();
   }
 | AnyCursor // Could be either ;| or ; |
   {
     suggestDdlAndDmlKeywords();
   }
 ;

UseStatement
 : 'USE' 'REGULAR_IDENTIFIER' 'PARTIAL_CURSOR'
   {
     suggestDatabases();
   }
 | 'USE' 'REGULAR_IDENTIFIER'
   {
     if (! parser.yy.cursorFound) {
       parser.yy.result.useDatabase = $2;
     }
   }
 | 'USE' 'CURSOR'
   {
     suggestDatabases();
   }
 ;

DataManipulation
 : LoadStatement
 | UpdateStatement
 ;

LoadStatement
 : HiveOrImpalaLoad HiveOrImpalaData HiveOrImpalaInpath HdfsPath 'INTO' 'TABLE' 'REGULAR_IDENTIFIER'
 | HiveOrImpalaLoad HiveOrImpalaData HiveOrImpalaInpath HdfsPath 'INTO' NoOrPartialRegularIdentifier
   {
     suggestKeywords([ 'TABLE' ]);
   }
 | HiveOrImpalaLoad HiveOrImpalaData HiveOrImpalaInpath HdfsPath NoOrPartialRegularIdentifier
   {
     suggestKeywords([ 'INTO' ]);
   }
 | HiveOrImpalaLoad HiveOrImpalaData HiveOrImpalaInpath HdfsPath
 | HiveOrImpalaLoad HiveOrImpalaData NoOrPartialRegularIdentifier
   {
     suggestKeywords([ 'INPATH' ]);
   }
 | HiveOrImpalaLoad NoOrPartialRegularIdentifier
   {
     suggestKeywords([ 'DATA' ]);
   }
 ;

HiveOrImpalaLoad
 : '<hive>LOAD'
 | '<impala>LOAD'
 ;

HiveOrImpalaData
 : '<hive>DATA'
 | '<impala>DATA'
 ;

HiveOrImpalaInpath
 : '<hive>INPATH'
 | '<impala>INPATH'
 ;

UpdateStatement
 : 'UPDATE' TargetTable 'SET' SetClauseList WhereClause
   {
     linkTablePrimaries();
   }
 | 'UPDATE' TargetTable 'SET' SetClauseList 'CURSOR'
   {
     suggestKeywords([ 'WHERE' ]);
   }
 | 'UPDATE' TargetTable 'SET' SetClauseList
   {
     linkTablePrimaries();
   }
 | 'UPDATE' TargetTable 'CURSOR'
   {
     suggestKeywords([ 'SET' ]);
   }
 | 'UPDATE' TargetTable
 | 'UPDATE' NoOrPartialRegularIdentifier
   {
     suggestTables();
     suggestDatabases({ appendDot: true });
   }
 ;

TargetTable
 : TableName
 ;

TableName
 : LocalOrSchemaQualifiedName
 ;

LocalOrSchemaQualifiedName
 : 'REGULAR_IDENTIFIER' AnyDot 'PARTIAL_CURSOR'
   {
     suggestTables({ database: $1 });
   }
 | 'REGULAR_IDENTIFIER' AnyDot 'REGULAR_IDENTIFIER' 'PARTIAL_CURSOR'
   {
     suggestTables({ database: $1 });
   }
 | 'REGULAR_IDENTIFIER' AnyDot 'REGULAR_IDENTIFIER'
   {
     addTablePrimary({ identifierChain: [{ name: $1 }, { name: $3 }] });
   }
 | 'REGULAR_IDENTIFIER'
   {
     addTablePrimary({ identifierChain: [{ name: $1 }] });
   }
 | 'REGULAR_IDENTIFIER' AnyDot
   {
     addTablePrimary({ identifierChain: [{ name: $1 }] });
   }
 ;

SetClauseList
 : SetClause
 | SetClauseList ',' SetClause
 ;

SetClause
 : SetTarget '=' UpdateSource
 | SetTarget 'CURSOR'
   {
     suggestKeywords([ '=' ]);
   }
 | NoOrPartialRegularIdentifier
   {
     suggestColumns();
   }
 ;

SetTarget
 : 'REGULAR_IDENTIFIER'
 ;

UpdateSource
 : ValueExpression
 ;

ValueExpression
 : BooleanValueExpression
 ;

TableDefinition
 : 'CREATE' TableScope 'TABLE' 'REGULAR_IDENTIFIER' TableElementList TableLocation
 | 'CREATE' NoOrPartialRegularIdentifier 'TABLE' 'REGULAR_IDENTIFIER' TableElementList
    {
      if (parser.yy.dialect === 'hive' || parser.yy.dialect === 'impala') {
        suggestKeywords(['EXTERNAL'])
      }
    }
 | 'CREATE' NoOrPartialRegularIdentifier 'TABLE' 'REGULAR_IDENTIFIER'
    {
      if (parser.yy.dialect === 'hive' || parser.yy.dialect === 'impala') {
        suggestKeywords(['EXTERNAL'])
      }
    }
 | 'CREATE' NoOrPartialRegularIdentifier 'TABLE'
    {
      if (parser.yy.dialect === 'hive' || parser.yy.dialect === 'impala') {
        suggestKeywords(['EXTERNAL'])
      }
    }
 | 'CREATE' TableScope 'TABLE' 'REGULAR_IDENTIFIER' TableElementList NoOrPartialRegularIdentifier
   {
     if (parser.yy.dialect === 'hive' || parser.yy.dialect === 'impala') {
       suggestKeywords(['LOCATION'])
     }
   }
 | 'CREATE' 'TABLE' 'REGULAR_IDENTIFIER' TableElementList
 | 'CREATE' NoOrPartialRegularIdentifier
    {
      if (parser.yy.dialect === 'hive' || parser.yy.dialect === 'impala') {
        suggestKeywords(['EXTERNAL', 'TABLE'])
      } else {
        suggestKeywords(['TABLE'])
      }
    }
 ;

TableScope
 : '<hive>EXTERNAL'
 | '<impala>EXTERNAL'
 ;

TableElementList
 : '(' TableElements ')'
 ;

TableElements
 : TableElement
 | TableElements ',' TableElement
 ;

TableElement
 : ColumnDefinition
 ;

ColumnDefinition
 : 'REGULAR_IDENTIFIER' PrimitiveType
 | 'REGULAR_IDENTIFIER' NoOrPartialRegularIdentifier
   {
     if (parser.yy.dialect == 'hive') {
       suggestKeywords(['BIGINT', 'BINARY', 'BOOLEAN', 'CHAR', 'DATE', 'DECIMAL', 'DOUBLE', 'FLOAT', 'INT', 'SMALLINT', 'TIMESTAMP', 'STRING', 'TINYINT', 'VARCHAR']);
     } else {
       suggestKeywords(['BIGINT', 'BOOLEAN', 'CHAR', 'DECIMAL', 'DOUBLE', 'FLOAT', 'INT', 'SMALLINT', 'TIMESTAMP', 'STRING', 'TINYINT', 'VARCHAR']);
     }
   }
 | 'REGULAR_IDENTIFIER' NoOrPartialRegularIdentifier ColumnDefinitionError error
   // error here is because it expects closing ')'
 ;

ColumnDefinitionError
 : /* empty, on error we should still suggest the keywords */
   {
     if (parser.yy.dialect == 'hive') {
       suggestKeywords(['BIGINT', 'BINARY', 'BOOLEAN', 'CHAR', 'DATE', 'DECIMAL', 'DOUBLE', 'FLOAT', 'INT', 'SMALLINT', 'TIMESTAMP', 'STRING', 'TINYINT', 'VARCHAR']);
     } else {
       suggestKeywords(['BIGINT', 'BOOLEAN', 'CHAR', 'DECIMAL', 'DOUBLE', 'FLOAT', 'INT', 'SMALLINT', 'TIMESTAMP', 'STRING', 'TINYINT', 'VARCHAR']);
     }
   }
 ;

TableLocation
 : HiveOrImpalaLocation HdfsPath
 ;

HiveOrImpalaLocation
 : '<hive>LOCATION'
 | '<impala>LOCATION'
 ;

HdfsPath
 : 'HDFS_START_QUOTE' 'HDFS_PATH' 'HDFS_END_QUOTE'
 | 'HDFS_START_QUOTE' 'HDFS_PATH' 'PARTIAL_CURSOR' 'HDFS_PATH' 'HDFS_END_QUOTE'
    {
      suggestHdfs({ path: $2 });
    }
 | 'HDFS_START_QUOTE' 'HDFS_PATH' 'PARTIAL_CURSOR' 'HDFS_END_QUOTE'
   {
     suggestHdfs({ path: $2 });
   }
 | 'HDFS_START_QUOTE' 'HDFS_PATH' 'PARTIAL_CURSOR'
    {
      suggestHdfs({ path: $2 });
    }
 | 'HDFS_START_QUOTE' 'PARTIAL_CURSOR' 'HDFS_END_QUOTE'
   {
     suggestHdfs({ path: '/' });
   }
 | 'HDFS_START_QUOTE' 'PARTIAL_CURSOR'
    {
      suggestHdfs({ path: '/' });
    }
 ;

AnyDot
 : '.'
 | '<impala>.'
 | '<hive>.'
 ;

// TODO: Support | DECIMAL(precision, scale)  -- (Note: Available in Hive 0.13.0 and later)
PrimitiveType
 : 'TINYINT'
 | 'SMALLINT'
 | 'INT'
 | 'BIGINT'
 | 'BOOLEAN'
 | 'FLOAT'
 | 'DOUBLE'
 | 'STRING'
 | 'DECIMAL'
 | 'CHAR'
 | 'VARCHAR'
 | 'TIMESTAMP'
 | '<hive>BINARY'
 | '<hive>DATE'
 ;

QueryExpression
 : 'SELECT' CleanUpSelectConditions SelectList TableExpression
   {
     linkTablePrimaries();
   }
 | 'SELECT' CleanUpSelectConditions SelectList
 ;

TableExpression
 : FromClause
 | FromClause SelectConditionList
 ;

CleanUpSelectConditions
 : /* empty */
   {
     delete parser.yy.afterGroupBy;
     delete parser.yy.afterLimit;
     delete parser.yy.afterOrderBy;
     delete parser.yy.afterWhere;
   }
 ;

FromClause
 : 'FROM' TableReferenceList
 | 'FROM' NoOrPartialRegularIdentifier
   {
     suggestTables();
     suggestDatabases({ appendDot: true });
   }
 ;

SelectConditionList
 : SelectCondition
 | SelectConditionList SelectCondition
 ;

SelectCondition
 : WhereClause
   {
     parser.yy.afterWhere = true;
   }
 | GroupByClause
   {
     parser.yy.afterGroupBy = true;
     delete parser.yy.result.suggestStar;
   }
 | OrderByClause
   {
     parser.yy.afterOrderBy = true;
     delete parser.yy.result.suggestStar;
   }
 | LimitClause
   {
     parser.yy.afterLimit = true;
     delete parser.yy.result.suggestStar;
   }
 | 'CURSOR'
   {
     var keywords = [];
     if (!parser.yy.afterGroupBy) {
       keywords.push('GROUP BY');
     }
     if (parser.yy.dialect === 'hive' && !parser.yy.afterGroupBy && !parser.yy.afterWhere && !parser.yy.afterOrderBy && !parser.yy.afterLimit) {
       keywords.push('LATERAL');
     }
     if (!parser.yy.afterLimit) {
       keywords.push('LIMIT');
     }
     if (!parser.yy.afterOrderBy) {
       keywords.push('ORDER BY');
     }
     if (!parser.yy.afterWhere) {
       keywords.push('WHERE');
     }
     if (keywords.length > 0) {
       suggestKeywords(keywords);
     }
   }
 ;

WhereClause
 : 'WHERE' SearchCondition
 | 'WHERE' 'CURSOR'
   {
     suggestColumns();
   }
 ;

SearchCondition
 : BooleanValueExpression
 ;

BooleanValueExpression
 : BooleanTerm
 | BooleanValueExpression 'OR' BooleanTerm
 ;

BooleanTerm
 : BooleanFactor
 | BooleanFactor 'AND' 'CURSOR'
   {
     // TODO: Fix issue when EOF after 'CURSOR' in started parenthesized expression it now throws a parser error
     suggestColumns();
   }
 | BooleanFactor 'AND' BooleanTerm
 ;

BooleanFactor
 : 'NOT' BooleanTest
 | BooleanTest
 ;

BooleanTest
 : Predicate
 | Predicate CompOp Predicate
 | Predicate CompOp AnyCursor
   {
     if (typeof $1 !== 'undefined') {
       suggestValues({ identifierChain: $1});
     }
   }
 | Predicate 'IS' TruthValue
 | Predicate 'IS' 'NOT' TruthValue
 ;

Predicate
 : ParenthesizedBooleanValueExpression
 | NonParenthesizedValueExpressionPrimary
   {
     $$ = $1;
   }
 ;

CompOp
 : '='
 | '<>'
 | '<'
 | '>'
 | '<='
 | '>='
 ;

ParenthesizedBooleanValueExpression
 : '(' BooleanValueExpression ')'
 | '(' AnyCursor // Could be either (| or ( |
   {
     // For '...FROM tableA JOIN tableB ON (|', might need an ON flag
     suggestColumns();
   }
 ;

SignedInteger
 : 'UNSIGNED_INTEGER'
 | '-' 'UNSIGNED_INTEGER'
 ;

StringValue
 : 'SINGLE_QUOTE' 'VALUE' 'SINGLE_QUOTE'
 ;

NonParenthesizedValueExpressionPrimary
 : ColumnReference // TODO: Expand with more choices
   {
     $$ = $1;
   }
 | SignedInteger
 | StringValue
 ;

ColumnReference
 : BasicIdentifierChain
   {
     $$ = $1;
   }
 ;

BasicIdentifierChain
 : InitIdentifierChain IdentifierChain
   {
     $$ = parser.yy.identifierChain
     delete parser.yy.identifierChain;
   }
 ;

InitIdentifierChain
 : /* empty */
   {
     parser.yy.identifierChain = [];
   }
 ;

IdentifierChain
 : Identifier
 | IdentifierChain AnyDot 'PARTIAL_CURSOR'
   {
     suggestColumns({
       identifierChain: parser.yy.identifierChain
     });
   }
 | IdentifierChain AnyDot Identifier
 ;

Identifier
 : 'REGULAR_IDENTIFIER'
   {
     parser.yy.identifierChain.push({ name: $1 });
   }
 | '"' 'REGULAR_IDENTIFIER' '"'
   {
     parser.yy.identifierChain.push({ name: $2 });
   }
 ;

GroupByClause
 : 'GROUP' 'BY' ColumnList
 | 'GROUP' NoOrPartialRegularIdentifier
   {
     suggestKeywords(['BY']);
   }
 ;

OrderByClause
 : 'ORDER' 'BY' ColumnList
 | 'ORDER' NoOrPartialRegularIdentifier
   {
     suggestKeywords(['BY']);
   }
 ;

LimitClause
 : 'LIMIT' 'UNSIGNED_INTEGER'
 | 'LIMIT' NoOrPartialRegularIdentifier
   {
     suggestNumbers([1, 5, 10]);
   }
 ;

SelectList
 : ColumnList
 | ColumnList NoOrPartialRegularIdentifier
   {
      suggestTables({ prependFrom: true });
      suggestDatabases({ prependFrom: true, appendDot: true });
    }
 | '*' NoOrPartialRegularIdentifier
   {
     suggestTables({ prependFrom: true });
     suggestDatabases({ prependFrom: true, appendDot: true });
   }
 | '*'
 ;

ColumnList
 : DerivedColumn
 | ColumnList ',' DerivedColumn
 ;

ColumnIdentifier
 : 'REGULAR_IDENTIFIER'
   {
     $$ = { name: $1 }
   }
 | 'REGULAR_IDENTIFIER' '[' 'DOUBLE_QUOTE' 'REGULAR_IDENTIFIER' 'DOUBLE_QUOTE' ']'
   {
     $$ = { name: $1, key: '"' + $4 + '"' }
   }
 | 'REGULAR_IDENTIFIER' '[' 'UNSIGNED_INTEGER' ']'
   {
     $$ = { name: $1, key: parseInt($3) }
   }
 | 'REGULAR_IDENTIFIER' '[' ']'
   {
     $$ = { name: $1, key: null }
   }
 ;

DerivedColumn
 : ColumnIdentifier
 | ColumnIdentifier AnyDot 'PARTIAL_CURSOR'
   {
     // TODO: Check if valid: SELECT testMap["key"].* FROM foo
     if (typeof $1.key === 'undefined') {
       parser.yy.result.suggestStar = true;
     }
     suggestColumns({
       identifierChain: [ $1 ]
     });
   }
 | ColumnIdentifier 'PARTIAL_CURSOR'
   {
     suggestColumns();
     suggestTables({ prependQuestionMark: true, prependFrom: true });
     suggestDatabases({ prependQuestionMark: true, prependFrom: true, appendDot: true });
   }
 | ColumnIdentifier AnyDot '*'
 | ColumnIdentifier AnyDot DerivedColumnChain
   {
      delete parser.yy.derivedColumnChain;
   }
 | ColumnIdentifier AnyDot DerivedColumnChain '<impala>.' 'PARTIAL_CURSOR'
   {
      parser.yy.derivedColumnChain.unshift($1);
      suggestColumns({
        identifierChain: parser.yy.derivedColumnChain
      });
      delete parser.yy.derivedColumnChain;
    }
 | ColumnIdentifier AnyDot DerivedColumnChain '<hive>.' 'PARTIAL_CURSOR'
   {
      parser.yy.derivedColumnChain.unshift($1);
      suggestColumns({
        identifierChain: parser.yy.derivedColumnChain
      });
      delete parser.yy.derivedColumnChain;
    }
 | 'CURSOR'
   {
     parser.yy.result.suggestStar = true;
     suggestColumns();
     suggestTables({ prependQuestionMark: true, prependFrom: true });
     suggestDatabases({ prependQuestionMark: true, prependFrom: true, appendDot: true });
   }
 ;

DerivedColumnChain
 : ColumnIdentifier
   {
     if (typeof parser.yy.derivedColumnChain === 'undefined') {
       parser.yy.derivedColumnChain = [];
     }
     parser.yy.derivedColumnChain.push($1);
     $$ = parser.yy.derivedColumnChain;
   }
 | DerivedColumnChain AnyDot ColumnIdentifier
   {
     parser.yy.derivedColumnChain.push($3);
     $$ = parser.yy.derivedColumnChain;
   }
 ;

TableReferenceList
 : TableReference
 | TableReferenceList ',' TableReference
 ;

TableReference
 : TablePrimaryOrJoinedTable
 ;

TablePrimaryOrJoinedTable
 : TablePrimary
 | JoinedTable
 ;

TablePrimary
 : 'REGULAR_IDENTIFIER'
   {
     addTablePrimary({ identifierChain: [ { name: $1 } ] });
   }
 | 'REGULAR_IDENTIFIER' LateralViews
   {
     addTablePrimary({ identifierChain: [ { name: $1 } ], lateralViews: $2 } );
   }
 | 'REGULAR_IDENTIFIER' 'REGULAR_IDENTIFIER'
   {
     addTablePrimary({ identifierChain: [ { name: $1 } ], alias: $2 });
   }
 | 'REGULAR_IDENTIFIER' 'REGULAR_IDENTIFIER' LateralViews
   {
     addTablePrimary({ identifierChain: [ { name: $1 } ], alias: $2, lateralViews: $3 } );
   }
 | 'REGULAR_IDENTIFIER' AnyDot 'REGULAR_IDENTIFIER'
   {
     addTablePrimary({ identifierChain: [ { name: $1 }, { name: $3 } ] });
   }
 | 'REGULAR_IDENTIFIER' AnyDot 'REGULAR_IDENTIFIER' 'REGULAR_IDENTIFIER'
   {
     addTablePrimary({ identifierChain: [ { name: $1 }, { name: $3 } ], alias: $4 });
   }
 | 'REGULAR_IDENTIFIER' AnyDot 'PARTIAL_CURSOR'
   {
     suggestTablesOrColumns($1);
   }
 ;

userDefinedTableGeneratingFunction
 : '<hive>explode' '(' DerivedColumnChain ')'
   {
     delete parser.yy.derivedColumnChain;
     $$ = { function: $1, expression: $3 }
   }
 | '<hive>posexplode' '(' DerivedColumnChain ')'
    {
      delete parser.yy.derivedColumnChain;
      $$ = { function: $1, expression: $3 }
    }
 ;

LateralViews
 : LateralView
   {
     if (typeof parser.yy.currentViews === 'undefined') {
       parser.yy.currentViews = [];
     }
     parser.yy.currentViews.push($1);
     $$ = parser.yy.currentViews;
   }
 | LateralViews LateralView
   {
     parser.yy.currentViews.push($2);
     $$ = parser.yy.currentViews;
   }
 ;

LateralView
 : '<hive>LATERAL' 'VIEW' userDefinedTableGeneratingFunction 'REGULAR_IDENTIFIER' LateralViewColumnAliases
   {
     $$ = { udtf: $3, tableAlias: $4, columnAliases: $5 }
   }
 | '<hive>LATERAL' 'VIEW' userDefinedTableGeneratingFunction LateralViewColumnAliases
    {
      $$ = { udtf: $3, columnAliases: $4 }
    }
 | '<hive>LATERAL' 'VIEW' userDefinedTableGeneratingFunction NoOrPartialRegularIdentifier
   {
     suggestKeywords(['AS']);
   }
 | '<hive>LATERAL' 'VIEW' NoOrPartialRegularIdentifier
   {
     suggestKeywords(['explode', 'posexplode']);
   }
 | '<hive>LATERAL' NoOrPartialRegularIdentifier
   {
     suggestKeywords(['VIEW']);
   }
 ;

LateralViewColumnAliases
 : '<hive>AS' 'REGULAR_IDENTIFIER'
   {
     $$ = [ $2 ]
   }
 | '<hive>AS' '(' 'REGULAR_IDENTIFIER' ',' 'REGULAR_IDENTIFIER' ')'
   {
     $$ = [ $3, $5 ]
   }
 ;

JoinedTable
 : TableReference 'JOIN' TableReference JoinSpecification
 | TableReference 'JOIN' 'CURSOR'
   {
     suggestTables({});
     suggestDatabases({ appendDot: true });
   }
 ;

JoinSpecification
 : JoinCondition
 ;

JoinCondition
 : 'ON' SearchCondition
 ;

%%

var prioritizeSuggestions = function () {
   parser.yy.result.lowerCase = parser.yy.lowerCase || false;
   if (typeof parser.yy.result.suggestIdentifiers !== 'undefined' &&  parser.yy.result.suggestIdentifiers.length > 0) {
     if (!parser.yy.keepColumns) {
      delete parser.yy.result.suggestColumns;
     }
     delete parser.yy.result.suggestTables;
     delete parser.yy.result.suggestDatabases;
     return;
   }
   if (typeof parser.yy.result.suggestColumns !== 'undefined') {
     if (typeof parser.yy.result.suggestColumns.table === 'undefined') {
       delete parser.yy.result.suggestColumns;
     } else {
       delete parser.yy.result.suggestTables;
       delete parser.yy.result.suggestDatabases;
     }
     return;
   }
}


/**
 * Impala supports referencing maps and arrays in the the table reference list i.e.
 *
 *  SELECT m['foo'].bar.| FROM someDb.someTable t, t.someMap m;
 *
 * From this the tablePrimaries would look like:
 *
 * [ { alias: 't', identifierChain: [ { name: 'someDb' }, { name: 'someTable' } ] },
 *   { alias: 'm', identifierChain: [ { name: 't' }, { name: 'someMap' } ] } ]
 *
 * with an identifierChain from the select list:
 *
 * [ { name: 'm', key: 'foo' }, { name: 'bar' } ]
 *
 * Calling this would return an expanded identifierChain, given the above it would be:
 *
 * [ { name: 't' }, { name: 'someMap', key: 'foo' }, { name: 'bar' } ]
 */
parser.expandImpalaIdentifierChain = function (tablePrimaries, identifierChain) {
  if (typeof identifierChain === 'undefined' || identifierChain.length === 0) {
    return identifierChain;
  }
  var firstIdentifier = identifierChain[0].name;

  foundPrimary = tablePrimaries.filter(function (tablePrimary) {
    return tablePrimary.alias === firstIdentifier;
  });

  if (foundPrimary.length === 1) {
    var firstPart = foundPrimary[0].identifierChain.concat();
    var secondPart = identifierChain.slice(1);
    if (typeof identifierChain[0].key !== 'undefined') {
      var lastFromFirst = firstPart.pop();
      firstPart.push({
        name: lastFromFirst.name,
        key: identifierChain[0].key
      })
    }
    return firstPart.concat(secondPart);
  }

  return identifierChain;
};

parser.expandLateralViews = function (tablePrimaries, identifierChain) {
  var firstIdentifier = identifierChain[0];
  var identifierChainParts = [];
  tablePrimaries.forEach(function (tablePrimary) {
    if (typeof tablePrimary.lateralViews !== 'undefined') {
      tablePrimary.lateralViews.reverse().forEach(function (lateralView) {
        if (firstIdentifier.name === lateralView.tableAlias && identifierChain.length > 1) {
          identifierChain.shift();
          firstIdentifier = identifierChain[0];
        } else if (firstIdentifier.name === lateralView.tableAlias && identifierChain.length === 1 && typeof parser.yy.result.suggestColumns !== 'undefined') {
          if (typeof parser.yy.result.suggestIdentifiers === 'undefined') {
            parser.yy.result.suggestIdentifiers = [];
          }
          lateralView.columnAliases.forEach(function (columnAlias) {
            parser.yy.result.suggestIdentifiers.push({ name: columnAlias, type: 'alias' });
          });
          delete parser.yy.result.suggestColumns;
          return identifierChain;
        }
        if (lateralView.columnAliases.indexOf(firstIdentifier.name) !== -1) {
          if (lateralView.columnAliases.length === 2 && lateralView.udtf.function.toLowerCase() === 'explode' && firstIdentifier.name === lateralView.columnAliases[0]) {
            identifierChain[0] = { name: 'key' };
          } else if (lateralView.columnAliases.length === 2 && lateralView.udtf.function.toLowerCase() === 'explode' && firstIdentifier.name === lateralView.columnAliases[1]) {
            identifierChain[0] = { name: 'value' };
          } else {
            identifierChain[0] = { name: 'item' };
          }
          identifierChain = lateralView.udtf.expression.concat(identifierChain);
          firstIdentifier = identifierChain[0];
        }
      });
    }
  });
  return identifierChain;
};

var linkSuggestion = function (suggestion, isColumnSuggestion) {
  var identifierChain = suggestion.identifierChain;
  var tablePrimaries = parser.yy.latestTablePrimaries;
  // Impala can have references to maps or array, i.e. FROM table t, t.map m
  // We need to replace those in the identifierChain
  if (parser.yy.dialect === 'impala') {
    identifierChain = parser.expandImpalaIdentifierChain(tablePrimaries, identifierChain);
    suggestion.identifierChain = identifierChain;
  }

  // Expand exploded views in the identifier chain
  if (parser.yy.dialect === 'hive') {
    if (identifierChain.length === 0) {
      if (typeof parser.yy.result.suggestIdentifiers === 'undefined') {
        parser.yy.result.suggestIdentifiers = [];
      }
      tablePrimaries.forEach(function (tablePrimary) {
        if (typeof tablePrimary.lateralViews !== 'undefined') {
          tablePrimary.lateralViews.forEach(function (lateralView) {
            if (typeof lateralView.tableAlias !== 'undefined') {
              parser.yy.result.suggestIdentifiers.push({ name: lateralView.tableAlias + '.', type: 'alias' });
              parser.yy.keepColumns = true;
            }
            lateralView.columnAliases.forEach(function (columnAlias) {
              parser.yy.result.suggestIdentifiers.push({ name: columnAlias, type: 'alias' });
              parser.yy.keepColumns = true;
            });
          });
        }
      });
    } else {
      identifierChain = parser.expandLateralViews(tablePrimaries, identifierChain);
      suggestion.identifierChain = identifierChain;
    }
  }

  // IdentifierChain contains a possibly started identifier or empty, example: a.b.c = ['a', 'b', 'c']
  // Reduce the tablePrimaries to the one that matches the first identifier if found
  if (identifierChain.length > 0) {
    var foundTable = tablePrimaries.filter(function (tablePrimary) {
      return identifierChain[0].name === tablePrimary.alias;
    });

    if (foundTable.length === 0) {
      foundTable = tablePrimaries.filter(function (tablePrimary) {
        return identifierChain[0].name === tablePrimary.identifierChain[0].name;
      })
    }

    if (foundTable.length === 1) {
      tablePrimaries = foundTable;
      identifierChain.shift();
    }
  }

  if (identifierChain.length == 0) {
    delete suggestion.identifierChain;
  }

  if (tablePrimaries.length === 1) {
    if (tablePrimaries[0].identifierChain.length == 2) {
      suggestion.database = tablePrimaries[0].identifierChain[0].name;
      suggestion.table = tablePrimaries[0].identifierChain[1].name;
    } else {
      suggestion.table = tablePrimaries[0].identifierChain[0].name;
    }
  } else if (tablePrimaries.length > 1 && isColumnSuggestion) {
    // Table identifier is required for column completion
    delete parser.yy.result.suggestColumns;
    suggestTablePrimariesAsIdentifiers();
  }
}

var suggestTablePrimariesAsIdentifiers = function () {
  if (typeof parser.yy.result.suggestIdentifiers === 'undefined') {
    parser.yy.result.suggestIdentifiers = [];
  }
  parser.yy.latestTablePrimaries.forEach(function (tablePrimary) {
    if (typeof tablePrimary.alias !== 'undefined') {
      parser.yy.result.suggestIdentifiers.push({ name: tablePrimary.alias + '.', type: 'alias' });
    } else {
      parser.yy.result.suggestIdentifiers.push({ name: tablePrimary.identifierChain[0].name + '.', type: 'table' });
    }
  });
}

var linkTablePrimaries = function () {
   if (!parser.yy.cursorFound) {
     return;
   }
   if (typeof parser.yy.result.suggestColumns !== 'undefined') {
     linkSuggestion(parser.yy.result.suggestColumns, true);
   }
   if (typeof parser.yy.result.suggestValues !== 'undefined') {
     linkSuggestion(parser.yy.result.suggestValues, false);
     if (parser.yy.latestTablePrimaries.length > 1) {
       suggestTablePrimariesAsIdentifiers();
     }
   }
}

var addTablePrimary = function (ref) {
  if (typeof parser.yy.latestTablePrimaries === 'undefined') {
    parser.yy.latestTablePrimaries = [];
  }
  parser.yy.latestTablePrimaries.push(ref);
}

var suggestNumbers = function (numbers) {
  parser.yy.result.suggestNumbers = numbers;
}

var suggestDdlAndDmlKeywords = function () {
  var keywords = ['ALTER', 'CREATE', 'DELETE', 'DESCRIBE', 'DROP', 'EXPLAIN', 'INSERT', 'REVOKE', 'SELECT', 'SET', 'SHOW', 'TRUNCATE', 'UPDATE', 'USE'];

  if (parser.yy.dialect == 'hive') {
    keywords = keywords.concat(['ANALYZE', 'EXPORT', 'IMPORT', 'LOAD', 'MSCK']);
  }

  if (parser.yy.dialect == 'impala') {
    keywords = keywords.concat(['COMPUTE', 'INVALIDATE', 'LOAD', 'REFRESH']);
  }
  keywords.sort();

  suggestKeywords(keywords);
}


var suggestKeywords = function (keywords) {
  parser.yy.result.suggestKeywords = keywords;
}

var suggestTablesOrColumns = function (identifier) {
  if (typeof parser.yy.latestTablePrimaries == 'undefined') {
    suggestTables({ database: identifier });
    return;
  }
  var tableRef = parser.yy.latestTablePrimaries.filter(function (tablePrimary) {
    return tablePrimary.alias === identifier;
  });
  if (tableRef.length > 0) {
    suggestColumns({ identifierChain: [ { name: identifier } ] });
  } else {
    suggestTables({ database: identifier });
  }
}

var suggestColumns = function (details) {
  parser.yy.result.suggestColumns = details || { identifierChain: [] };
}

var suggestTables = function (details) {
  parser.yy.result.suggestTables = details || {};
}

var suggestDatabases = function (details) {
  parser.yy.result.suggestDatabases = details || {};
}

var suggestHdfs = function (details) {
  parser.yy.result.suggestHdfs = details || {}
}

var suggestValues = function (details) {
  parser.yy.result.suggestValues = details || { identifierChain: [] }
}

var determineCase = function (text) {
  parser.yy.lowerCase = text.toLowerCase() === text;
};

var lexerModified = false;

/**
 * Main parser function
 */
parser.parseSql = function(beforeCursor, afterCursor, dialect) {
  parser.yy.activeDialect = dialect;

  // Hack to set the inital state of the lexer without first having to hit a token
  // has to be done as the first token found can be dependant on dialect
  if (!lexerModified && typeof dialect !== 'undefined') {
    var originalSetInput = parser.lexer.setInput;
    parser.lexer.setInput = function (input) {
      var lexer = originalSetInput.bind(parser.lexer)(input);
      if (typeof parser.yy.activeDialect !== 'undefined') {
        lexer.begin(parser.yy.activeDialect)
      }
    }
    lexerModified = true;
  }

  var result;
  parser.yy.dialect = dialect;
  try {
    // Add |CURSOR| or |PARTIAL_CURSOR| to represent the different cursor states in the lexer
    result = parser.parse(beforeCursor + (beforeCursor.length == 0 || beforeCursor.indexOf(' ', beforeCursor.length - 1) !== -1 ? ' |CURSOR| ' : '|PARTIAL_CURSOR|') + afterCursor);
  } catch (err) {
    // On any error try to at least return any existing result
    if (typeof parser.yy.result === 'undefined') {
      throw err;
    }
    result = parser.yy.result;
  }

  if (typeof result.error !== 'undefined' && typeof result.error.expected !== 'undefined') {
    // Remove any expected tokens from other dialects, jison doesn't remove tokens from other lexer states.
    var actualExpected = [];
    result.error.expected.forEach(function (expected) {
      var match = expected.match(/\<([a-z]+)\>(.*)/);
      if (match !== null) {
        if (typeof parser.yy.dialect !== 'undefined' && parser.yy.dialect === match[1]) {
          actualExpected.push(match[2]);
        }
      } else {
        actualExpected.push(expected);
      }
    });
    result.error.expected = actualExpected;
  }

  if (typeof result.error !== 'undefined' && result.error.recoverable) {
    delete result.error;
  }

  return result;
}

/*
 Hive Select syntax from https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

 [WITH CommonTableExpression (, CommonTableExpression)*]    (Note: Only available starting with Hive 0.13.0)
 SELECT [ALL | DISTINCT] select_expr, select_expr, ...
 FROM table_reference
 [WHERE where_condition]
 [GROUP BY col_list]
 [CLUSTER BY col_list
   | [DISTRIBUTE BY col_list] [SORT BY col_list]
 ]
 [LIMIT number]
*/