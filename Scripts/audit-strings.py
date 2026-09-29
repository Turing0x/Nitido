#!/usr/bin/env python3
"""Audita Localizable.xcstrings contra las claves usadas en el código.

Falla (exit 1) si una clave usada no está en el catálogo o le falta es/en.
Uso, desde la raíz del repo: python3 Scripts/audit-strings.py
"""
import sys
import json,re,glob
d=json.load(open('Nitido/Resources/Localizable.xcstrings'))['strings']
used={}
for f in glob.glob('Nitido/**/*.swift',recursive=True):
    s=open(f).read()
    for m in re.finditer(r'localized:\s*"([^"]+)"\s*,\s*defaultValue:\s*"((?:[^"\\]|\\.)*)"',s):
        used[m.group(1)]=(m.group(2),f)
print("usadas",len(used),"catalogo",len(d))
print("\nFALTAN EN CATALOGO:")
for k,(v,f) in sorted(used.items()):
    if k not in d: print(" ",k,"|",v[:90],"|",f.split('/')[-1])
print("\nINCOMPLETAS (sin es o en):")
for k,v in sorted(d.items()):
    l=v.get('localizations',{})
    miss=[x for x in('es','en') if x not in l]
    if miss: print(" ",k,miss)
print("\nHUERFANAS:",[k for k in d if k not in used][:30])

bad=[k for k,(v,f) in used.items() if k not in d] + [k for k,v in d.items() if any(x not in v.get('localizations',{}) for x in ('es','en'))]
sys.exit(1 if bad else 0)
