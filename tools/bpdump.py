"""Compact view of a Blueprint function's bytecode from an ffr-dump JSON (FFR_SCRIPT=1).
usage: python tools/bpdump.py <json> <FunctionName>"""
import json, sys

def name(o):
    if isinstance(o, dict):
        for k in ('ObjectName', 'Name'):
            if k in o and isinstance(o[k], str):
                return o[k].split(':')[-1].strip("'")
        if 'Property' in o:
            return name(o['Property'])
        if 'Variable' in o:
            return name(o['Variable'])
    return str(o)

def expr(e, d=0):
    if not isinstance(e, dict):
        return str(e)
    t = e.get('Token', '?')
    if t in ('EX_LocalVariable', 'EX_InstanceVariable', 'EX_LocalOutVariable', 'EX_DefaultVariable'):
        return name(e.get('Variable'))
    if t.endswith('Const') or t in ('EX_True', 'EX_False', 'EX_NoObject', 'EX_Self'):
        return t[3:] + ('(' + str(e.get('Value')) + ')' if 'Value' in e else '')
    if 'Function' in e or 'StackNode' in e or 'VirtualFunctionName' in e:
        f = e.get('Function') or e.get('StackNode') or e.get('VirtualFunctionName')
        args = ', '.join(expr(p, d + 1) for p in e.get('Parameters', []))
        return name(f) + '(' + args + ')'
    if t == 'EX_Context' or t == 'EX_Context_FailSilent':
        return expr(e.get('ObjectExpression'), d) + '.' + expr(e.get('ContextExpression'), d)
    if t in ('EX_Let', 'EX_LetBool', 'EX_LetObj', 'EX_LetValueOnPersistentFrame'):
        return expr(e.get('Variable') or e.get('VariableExpression'), d) + ' = ' + expr(e.get('Expression') or e.get('AssignmentExpression'), d)
    if t in ('EX_JumpIfNot',):
        return 'if not ' + expr(e.get('BooleanExpression'), d) + ' goto ' + str(e.get('CodeOffset'))
    if t in ('EX_StructMemberContext',):
        return expr(e.get('StructExpression'), d) + '.' + name(e.get('Property'))
    return t[3:]

d = json.load(open(sys.argv[1], encoding='utf8'))
for ex in d:
    if ex.get('Name') == sys.argv[2] and 'ScriptBytecode' in ex:
        for st in ex['ScriptBytecode']:
            print(st.get('StatementIndex'), expr(st))
