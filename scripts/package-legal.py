#!/usr/bin/env python3
"""Render and bundle the project's small, controlled Markdown legal documents."""
from pathlib import Path
import html
import re
import shutil
import sys
root = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'Resources' / 'Legal'
output.mkdir(parents=True, exist_ok=True)
names = ['PRIVACY.md', 'TERMS.md', 'DATA-DELETION.md', 'SECURITY.md', 'THIRD-PARTY-NOTICES.md', 'LICENSE']
def inline(value):
    value = html.escape(value)
    value = re.sub(r'`([^`]+)`', r'<code>\1</code>', value)
    value = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', value)
    def link(match):
        label, url = match.groups()
        if url in names:
            url = url.removesuffix('.md') + '.html'
        return f'<a href="{url}">{label}</a>'
    return re.sub(r'\[([^]]+)\]\(([^)]+)\)', link, value)
for name in names:
    text = (root / name).read_text()
    blocks = []
    for block in text.strip().split('\n\n'):
        lines = block.splitlines()
        if name == 'LICENSE':
            blocks.append('<p>' + html.escape(block).replace('\n', '<br>') + '</p>')
        elif lines[0].startswith('#'):
            level = len(lines[0]) - len(lines[0].lstrip('#'))
            blocks.append(f'<h{level}>' + inline(lines[0][level:].strip()) + f'</h{level}>')
        elif lines[0].startswith('|'):
            rows = [line for line in lines if not re.fullmatch(r'[| :\-]+', line)]
            blocks.append('<table>' + ''.join('<tr>' + ''.join('<td>' + inline(cell.strip()) + '</td>' for cell in row.strip('|').split('|')) + '</tr>' for row in rows) + '</table>')
        elif lines[0].startswith('- ') or re.match(r'\d+\. ', lines[0]):
            tag = 'ul' if lines[0].startswith('- ') else 'ol'
            blocks.append(f'<{tag}>' + ''.join('<li>' + inline(re.sub(r'^(?:- |\d+\. )', '', line)) + '</li>' for line in lines) + f'</{tag}>')
        else:
            blocks.append('<p>' + inline(' '.join(lines)) + '</p>')
    title = 'Margin License' if name == 'LICENSE' else text.splitlines()[0].lstrip('# ')
    document = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>' + html.escape(title) + '</title><style>html{color-scheme:light dark}body{font:16px/1.65 system-ui,sans-serif;max-width:760px;margin:48px auto;padding:0 24px}h1{font-size:30px;line-height:1.2}h2{font-size:21px;margin-top:32px}a{color:LinkText}code{font-size:.9em;overflow-wrap:anywhere}table{border-collapse:collapse;width:100%}td{border:1px solid GrayText;padding:10px;vertical-align:top}li{margin:8px 0}</style><article>' + ''.join(blocks) + '</article></html>'
    (output / (name.removesuffix('.md') + '.html')).write_text(document)
    shutil.copyfile(root / name, output / name)
shutil.copyfile(root / '.build/sparkle-2.9.6/LICENSE', output / 'Sparkle-LICENSE.txt')
