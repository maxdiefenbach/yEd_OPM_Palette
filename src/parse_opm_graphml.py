#!/usr/bin/env python3
"""
Script to extract nodes and edges from a yEd GraphML palette file,
using BeautifulSoup4 for XML parsing. Outputs JSON with two arrays:
- nodes: each with id, tooltip, shape_type, border_type, dropshadow, is_group
- edges: each with id, tooltip, source, target, arrow_tail, arrow_head, tag

Usage:
    python3 parse_opm_graphml.py path/to/input.graphml
    python3 parse_opm_graphml.py path/to/input.graphml -o path/to/output.csv
"""

import argparse
import json
from bs4 import BeautifulSoup
import pandas as pd


# Columns shown in the stdout summary table, in display order. The CSV keeps
# every extracted column; this is only the human-readable subset.
SUMMARY_COLUMNS = [
    "id",
    "tooltip",
    "thing_type",
    "state_type",
    "essence",
    "affiliation",
    "is_group",
    "edge_type",
    "tags",
]


def extract_nodes(soup):
    """Extract and classify node definitions from a yEd GraphML soup.

    For each <node> element, this collects basic visual attributes from the
    yEd/YFiles extension elements and derives OPM-oriented classifications.

    Returned node dictionaries contain at least:
    - id: GraphML node id
    - tooltip: palette tooltip text (data[key=<palette_node_key>])
    - shape_type: y:Shape/@type (e.g. "rectangle", "roundrectangle", "ellipse")
    - border_type: y:BorderStyle/@type (e.g. "line", "dashed")
    - dropshadow: whether a y:DropShadow element is present
    - is_group: whether this node is a yFiles group (yfiles.foldertype="group")
    - thing_type: "object", "process" or "state" (for rounded rectangles)
    - state_type: for states, one of "initial", "final", "ordinary"; otherwise None
    - essence: "physical" or "informational" for non-state nodes, "" for states
    - affiliation: "systemic" or "environmental" for non-state nodes, "" for states

    The key used for the palette tooltip is looked up dynamically from the
    <key> elements with attr.name="Palette ToolTip" to guard against cases
    where the id is not "d4".

    Parameters
    ----------
    soup: bs4.BeautifulSoup
        Parsed GraphML document using the "xml" parser.

    Returns
    -------
    list[dict]
        List of node dictionaries with visual attributes and OPM classifications.
    """
    # Discover the GraphML key id used for node palette tooltips
    node_tooltip_key = None
    for key in soup.find_all("key"):
        if key.get("for") == "node" and key.get("attr.name") == "Palette ToolTip":
            node_tooltip_key = key.get("id")
            break

    nodes = []
    for node in soup.find_all("node"):
        nid = node.get("id")
        # Get palette tooltip via discovered key id (e.g. d4)
        tooltip_elem = None
        if node_tooltip_key is not None:
            tooltip_elem = node.find("data", {"key": node_tooltip_key})
        tooltip = (
            tooltip_elem.text.strip() if tooltip_elem and tooltip_elem.text else ""
        )
        # Shape type under <Shape>
        shape_elem = node.find("Shape")
        shape_type = (
            shape_elem.get("type")
            if shape_elem and shape_elem.has_attr("type")
            else None
        )
        # Border style under <BorderStyle>
        border_elem = node.find("BorderStyle")
        border_type = (
            border_elem.get("type")
            if border_elem and border_elem.has_attr("type")
            else None
        )
        dash_style = (
            border_elem.get("dashStyle")
            if border_elem and border_elem.has_attr("dashStyle")
            else None
        )
        border_width = (
            border_elem.get("width")
            if border_elem and border_elem.has_attr("width")
            else None
        )
        # DropShadow presence
        dropshadow = node.find("DropShadow") is not None
        # Determine if this is a group node (foldertype="group")
        is_group = node.get("yfiles.foldertype") == "group"

        # Derive thing_type from shape
        # States are modeled as rounded rectangles
        if shape_type == "rectangle":
            thing_type = "object"
        elif shape_type == "roundrectangle":
            thing_type = "state"
        elif shape_type == "ellipse":
            thing_type = "process"
        else:
            thing_type = None

        if thing_type == "state":
            essence = ""
            affiliation = ""
            try:
                width_val = float(border_width) if border_width is not None else 1.0
            except ValueError:
                width_val = 1.0
            is_thick = width_val >= 3.0
            is_dashed = dash_style not in (None, "solid")

            if is_thick and not is_dashed:
                state_type = "initial"
            elif is_thick and is_dashed:
                state_type = "final"
            else:
                state_type = "ordinary"
        else:
            essence = "physical" if dropshadow else "informational"
            state_type = None

            # Derive affiliation primarily from border_type (not for states)
            # In the palette GraphML, environmental things use a dashed border
            # (border_type == "dashed"), systemic things use a solid line
            # (border_type == "line"). For any other types we fall back to
            # the dashStyle convention.
            if border_type == "dashed":
                affiliation = "environmental"
            elif border_type == "line" or border_type is None:
                # Solid or unspecified border type -> use dashStyle
                affiliation = (
                    "environmental" if dash_style not in (None, "solid") else "systemic"
                )
            else:
                # Unexpected border_type, fall back to dashStyle
                affiliation = (
                    "environmental" if dash_style not in (None, "solid") else "systemic"
                )

        node  = {
                "id": nid,
                "thing_type": thing_type,
                "essence": essence,
                "affiliation": affiliation,
                "is_group": is_group,
                "state_type": state_type,
                "shape_type": shape_type,
                "border_type": border_type,
                "dropshadow": dropshadow,
                "tooltip": tooltip,
            }

        nodes.append(
            {k: v for k, v in node.items() if v is not None}
        )
    return nodes


def extract_edges(soup):
    """Extract edge definitions from a yEd GraphML soup.

    For each <edge> element, this collects:
    - id: GraphML edge id
    - tooltip: palette tooltip text (data[key=<palette_edge_key>]) – informational only
    - source: id of the source node
    - target: id of the target node
    - arrow_tail: y:Arrows/@source (tail marker type)
    - arrow_head: y:Arrows/@target (head marker type)
    - tags: list of texts from any y:EdgeLabel elements
    - edge_type: semantic classification derived solely from arrow_tail/head

    Edge types are determined by the arrow marker combination and mapped to
    the conceptual classes represented in the palette tooltips. Tooltips are
    not used as input for classification and are only retained for reference.

    The key used for the palette tooltip is looked up dynamically from the
    <key> elements with attr.name="Palette ToolTip" to guard against cases
    where the id is not "d9".

    Parameters
    ----------
    soup: bs4.BeautifulSoup
        Parsed GraphML document using the "xml" parser.

    Returns
    -------
    list[dict]
        List of edge dictionaries with basic visual/semantic attributes.
    """
    # Discover the GraphML key id used for edge palette tooltips
    edge_tooltip_key = None
    for key in soup.find_all("key"):
        if key.get("for") == "edge" and key.get("attr.name") == "Palette ToolTip":
            edge_tooltip_key = key.get("id")
            break

    edges = []
    for edge in soup.find_all("edge"):
        eid = edge.get("id")
        src = edge.get("source")
        tgt = edge.get("target")
        # Get palette tooltip via discovered key id (e.g. d9) – kept for reference only
        tooltip_elem = None
        if edge_tooltip_key is not None:
            tooltip_elem = edge.find("data", {"key": edge_tooltip_key})
        tooltip = (
            tooltip_elem.text.strip() if tooltip_elem and tooltip_elem.text else ""
        )
        # Get arrow definitions under <Arrows>
        arrows = edge.find("Arrows")
        arrow_tail = (
            arrows.get("source") if arrows and arrows.has_attr("source") else None
        )
        arrow_head = (
            arrows.get("target") if arrows and arrows.has_attr("target") else None
        )
        # Extract text from any <EdgeLabel> elements
        tags = [
            lbl.get_text(strip=True)
            for lbl in edge.find_all("EdgeLabel")
            if lbl.get_text(strip=True)
        ]

        # Normalize arrow markers to simple strings
        tail = arrow_tail or "none"
        head = arrow_head or "none"

        # Classify edge_type based solely on arrow markers.
        # The mapping between (tail, head) and conceptual edge classes is
        # derived from the palette documentation in
        # ``yEd_OPM_Palette_Document.graphml`` where each edge tooltip names
        # the class for a specific arrow combination. We hard-code that
        # mapping here so that tooltips are not needed at runtime.
        if tail == "none" and head == "delta":
            edge_type = "aggregation--participation"
        elif tail == "none" and head == "diamond":
            edge_type = "exhibition--characterization"
        elif tail == "none" and head == "white_delta_bar":
            edge_type = "generalization--specialization"
        elif tail == "none" and head == "convex":
            edge_type = "classification--instantiation"
        elif tail == "none" and head == "transparent_circle" and "e" in tags:
            edge_type = "instrument_effect"
        elif tail == "none" and head == "transparent_circle":
            edge_type = "instrument"
        elif tail == "none" and head == "circle" and "e" in tags:
            edge_type = "agent_effect"
        elif tail == "none" and head == "circle":
            edge_type = "agent"
        elif tail == "none" and head == "white_delta":
            edge_type = "consumption"
        elif tail == "white_delta" and head == "white_delta":
            edge_type = "effect"
        elif tail == "none" and head == "plain":
            edge_type = "tagged_structural"
        elif tail == "none" and head == "crows_foot_many":
            edge_type = "xor"
        elif tail == "none" and head == "crows_foot_many_mandatory":
            edge_type = "or"
        elif tail == "crows_foot_one" and head == "none":
            edge_type = "overtime"
        elif tail == "crows_foot_one_mandatory" and head == "none":
            edge_type = "undertime"
        else:
            # Default: encode raw combination for unmapped cases
            edge_type = f"{tail}->{head}"

        edges.append(
            {
                "id": eid,
                "tooltip": tooltip,
                "source": src,
                "target": tgt,
                "arrow_tail": arrow_tail,
                "arrow_head": arrow_head,
                "tags": tags,
                "edge_type": edge_type,
            }
        )
    return edges


def main(filepath, output_path=None):
    """Parse a yEd GraphML palette file and emit JSON/CSV summaries.

    The script reads the given GraphML file, extracts nodes and edges using
    BeautifulSoup-based helpers, and prints a JSON representation plus a
    summary table to stdout. A flattened CSV (nodes + edges) is written only
    when ``output_path`` is given.

    Parameters
    ----------
    filepath: str
        Path to the yEd GraphML palette file.
    output_path: str | None
        Path where the flattened CSV output should be written, or None to
        skip writing a CSV.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f, "xml")

    nodes = extract_nodes(soup)
    edges = extract_edges(soup)
    output = {"nodes": nodes, "edges": edges}
    print(json.dumps(output, indent=2))
    df = pd.json_normalize(nodes + edges)
    pd.set_option("display.max_rows", None)
    # Node and edge dicts omit keys that do not apply (e.g. no state_type when
    # the graph has no states), so only summarize the columns actually present.
    print(df[[column for column in SUMMARY_COLUMNS if column in df.columns]])
    if output_path:
        df.to_csv(output_path, index=False)


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Extract nodes and edges from a yEd GraphML palette file."
    )
    parser.add_argument(
        "filepath",
        help="Path to the yEd GraphML palette file.",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="Path where the flattened CSV output should be written. "
        "Omit to print the summaries without writing a CSV.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    main(args.filepath, args.output)
