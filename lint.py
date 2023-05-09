#!/usr/bin/python3
from xml.etree import ElementTree as ET
import re
import yaml
import json
import inspect
import os
import glob
import logging

CODE_URL = "https://github.com/galaxyproject/tools-iuc/wiki/Error-Codes"

def delete_text(path="", idx=0, text="", message="No message", code="IUC000", full_line=""):
    return error(path=path, idx=idx, match_start=0, match_end=len(text), replacement="", message=message, code=code, full_line=full_line)

def file_error(path="", message="No message", code="IUC000"):
    return error(path=path, idx=0, match_start=0, match_end=1, replacement=None, message=message, code=code, full_line="")

def warning(path="", idx=0, match_start=0, match_end=1, replacement=None, message="No message", code="IUC000", full_line=""):
    return rdjson_message(path=path, idx=idx, match_start=match_start, match_end=match_end, replacement=replacement, message=message, code=code, full_line=full_line, level="warning")

def error(path="", idx=0, match_start=0, match_end=1, replacement=None, message="No message", code="IUC000", full_line=""):
    return rdjson_message(path=path, idx=idx, match_start=match_start, match_end=match_end, replacement=replacement, message=message, code=code, full_line=full_line, level="error")

# Ruby: def self.message(path: "", idx: 0, match_start: 0, match_end: 1, replacement: nil, message: "No message", level: "WARNING", code: "GTN000", full_line: "")
def rdjson_message(path="", idx=0, match_start=0, match_end=1, replacement=None, message="No message", level="WARNING", code="GTN000", full_line=""):
    end_area = {"line": idx + 1, "column": match_end}
    if match_end == len(full_line):
        end_area = {"line": idx + 2, "column": 1}

    res = {"message": message, "location": {
        "path": path, "range": {"start": {"line": idx + 1, "column": match_start + 1}, "end": end_area}}, "severity": level}

    if code is not None:
        res["code"] = {"value": code, "url": CODE_URL + "#" + code.lower()}

    if replacement is not None:
        res["suggestions"] = [{"text": replacement, "range": {
            "start": {"line": idx + 1, "column": match_start + 1}, "end": end_area}}]
    return res


class IucLinter:
    def __init__(self):
        self.errors = []

    def lint_missing_shed_yml(self, path):
        if not os.path.exists(os.path.join(path, '.shed.yml')):
            yield file_error(path=path, message="Missing shed.yml file", code="IUC001")

    def lint_shed_yml_contents(self, path):
        yaml_path = os.path.join(path, '.shed.yml')
        if not os.path.exists(yaml_path):
            return

        with open(yaml_path) as handle:
            shed_contents = handle.read()
            shed = yaml.safe_load(shed_contents)

        if shed.get('categories') is None:
            yield error(path=yaml_path, message="Missing categories in shed.yml file", code="IUC002")
        if shed.get('description') in (None, ""):
            yield error(path=yaml_path, message="Missing description in shed.yml file", code="IUC003")
        #  Are there homepage_url and remote_repository_url fields?
        if shed.get('homepage_url') in (None, ""):
            yield error(path=yaml_path, message="Missing homepage_url in shed.yml file", code="IUC004")
        if shed.get('remote_repository_url') in (None, ""):
            yield error(path=yaml_path, message="Missing remote_repository_url in shed.yml file", code="IUC005")
        #  Does the name match the folder name and
        folder_name = os.path.basename(os.path.dirname(yaml_path))

        if 'name' in shed:
            if shed.get('name') != os.path.basename(folder_name):
                yield error(path=yaml_path, message="Name in shed.yml does not match folder name", code="IUC006")
            # The name must be Alphanumeric and underscore _ only, no - (and apparently not .)
            if not re.match(r'^[a-z0-9_]+$', shed.get('name', "")):
                yield error(path=yaml_path, message="Name in shed.yml contains invalid characters", code="IUC007")
        # No TODOs anywhere in the shed.yml file
        if 'TODO' in shed_contents:
            yield error(path=yaml_path, message="TODO found in shed.yml", code="IUC008")

    def is_tool(self, tool_xml):
        with open(tool_xml) as handle:
            tool_contents = handle.read()
            return '<tool' in tool_contents
        return False

    def is_macro(self, tool_xml):
        root = ET.parse(tool_xml).getroot()
        return root.tag == 'macros'

    def discover_tool_xmls(self, path):
        tools = []
        for tool_xml in glob.glob(os.path.join(path, "*.xml")):
            if self.is_tool(tool_xml):
                tools.append(tool_xml)
        return tools

    def discover_macros_xmls(self, path):
        tools = []
        for tool_xml in glob.glob(os.path.join(path, "*.xml")):
            if self.is_macro(tool_xml):
                tools.append(tool_xml)
        return tools

    def check_tool_xml(self, tool_xml):
        with open(tool_xml) as handle:
            tool_contents = handle.read()
            root = ET.fromstring(tool_contents)

        if 'TODO' in tool_contents:
            yield error(path=tool_xml, message="TODO found in tool XML", code="IUC010")

        # Find the <tool> node
        if root.tag != 'tool':
            # print("No tool node found in %s" % tool_xml)
            return

        # Check that the version is @TOOL_VERSION@
        if root.get('version') not in ('@TOOL_VERSION@', '@TOOL_VERSION@+galaxy@VERSION_SUFFIX@'):
            yield file_error(path=tool_xml, message=f"Tool version is not correct ({root.get('version')}), it should be a macro @TOOL_VERSION@ or @TOOL_VERSION@+galaxy@VERSION_SUFFIX@", code="IUC011")

        # Check that a description tag exists and it's contents are longer than 50 characters:
        description = root.find('description')
        description_text = description.text if (description is not None) else None
        if description is None or description_text is None:
            yield error(path=tool_xml, message="Tool XML is missing a description", code="IUC012")
        elif len(description_text) < 30:
            yield error(path=tool_xml, message="Tool XML description is too short", code="IUC013")

        # check that a profile is set on the tool
        if root.get('profile') is None:
            yield error(path=tool_xml, message="Tool XML is missing a profile", code="IUC015")
        # Check that the command block checks exit code
        command = root.find('command')
        if command is not None:
            error_checking = command.get('detect_errors')
            if error_checking != 'exit_code':
                yield error(path=tool_xml, message=f"Command block does not check exit code ({error_checking}), this is generally recommended.", code="IUC016")

        # Lint improperly quoted variables in command
        if root.find('command') is not None:
            command_text = root.find('command').text
            stripped_cheetah = [re.sub('#.*', '', x) for x in command_text.split('\n')]
            bad_pattern = r'(?P<lq>[\'"])?(?P<ch>\${?[a-zA-Z0-9_.]+}?)(?P<rq>[\'"])?'
            p = re.compile(bad_pattern)

            for line in stripped_cheetah:
                for m in re.finditer(p, line):
                    # n^3
                    if m.group('lq') is None or m.group('rq') is None:
                        line_number = [i for (i, x) in enumerate(tool_contents.split('\n')) if line in x][0]

                        yield error(path=tool_xml, message=f"Variable in command is potentially improperly quoted: {m[1]}", code="IUC018", idx=line_number, match_start=m.start('ch'), match_end=m.end('ch'))

        # TODO: expand macros

        # A version_command must be present
        version_command = root.find('version_command')
        if version_command is None:
            yield error(path=tool_xml, message="Tool XML is missing a version_command", code="IUC017")

    def lint_has_tools(self, path):
        discovered_tools = self.discover_tool_xmls(path)
        if not discovered_tools:
            yield error(path=path, message="No tools found", code="IUC009")
        else:
            for tool_xml in discovered_tools:
                yield from self.check_tool_xml(tool_xml)

            #  If there is more than one tool present (tool collection), is there a macros.xml file?
            if len(discovered_tools) > 1:
                macros = self.discover_macros_xmls(path)
                if len(macros) == 0:
                    yield error(path=path, message="Tool collection with no macros.xml file", code="IUC014")

    def discover_linters(self):
        for name, func in inspect.getmembers(self, predicate=inspect.ismethod):
            if name.startswith('lint_'):
                yield func

    def check_repo(self, path):
        for linter in self.discover_linters():
            yield from linter(path)

    def process_repo(self, path):
        self.errors += list(self.check_repo(path))

    def discover_repos(self):
        for path in glob.glob('tools/*'):
            #print(path)
            if os.path.isdir(path):
                logging.info("Checking %s", path)
                process_repo(path)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--path', help='A specific path to lint, rather than discovering all files')
    parser.add_argument('--verbose', '-v', action='store_true')
    args = parser.parse_args()

    linter = IucLinter()
    if args.path:
        linter.process_repo(args.path)
    else:
        linter.discover_repos()

    for x in linter.errors:
        print(json.dumps(x))
