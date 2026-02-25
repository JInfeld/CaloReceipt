sv import from ingredient {
    ParseReceiptTextToPantry,
    ParseReceiptImageToPantry
}

def:pub ReceiptUploadTab() -> JsxElement {
    has loading: bool = false;
    has status_text: str = "Upload a receipt image, parse it with API, review items, and add to pantry.";

    has receipt_file_name: str = "";
    has receipt_image_b64: str = "";
    has receipt_image_mime_type: str = "image/jpeg";

    has extracted_text: str = "";
    has parsed_rows: list = [];
    has pantry_items: list = [];
    has receipt_parse_payload: dict = {};

    def first_report_payload(raw_result: dict) -> dict {
        if raw_result.reports and raw_result.reports.length > 0 {
            return raw_result.reports[0];
        }
        if raw_result.data and raw_result.data.reports and raw_result.data.reports.length > 0 {
            return raw_result.data.reports[0];
        }
        if raw_result.data and raw_result.data.result {
            return raw_result.data.result;
        }
        if raw_result.result {
            return raw_result.result;
        }
        return raw_result;
    }

    def normalize_unit(raw: str) -> str {
        text = String(raw).trim().toUpperCase();
        if text == "LB" {
            return "LB";
        }
        if text == "OZ" {
            return "OZ";
        }
        return "PIECE";
    }

    def stage_rows_from_items(items: list) -> None {
        rows: list = [];
        row_id = 1;
        for item in items {
            item_name = String(item.name or "").trim();
            if not item_name {
                continue;
            }
            rows = rows.concat([{
                "row_id": row_id,
                "name": item_name,
                "quantity_text": String(item.quantity or 1),
                "unit": normalize_unit(String(item.unit or "PIECE"))
            }]);
            row_id += 1;
        }
        parsed_rows = rows;
    }

    def parse_receipt_output(raw_text: str) -> list {
        rows: list = [];
        next_id = 1;
        for line in raw_text.split("\n") {
            clean = line.trim();
            if not clean {
                continue;
            }
            tokens = clean.split(" ").filter(
                lambda part: str -> bool { return part.trim().length > 0; }
            );

            item_name = clean;
            qty_text = "1";

            if tokens.length >= 2 {
                qty_text = tokens[tokens.length - 1];
                item_name = tokens.slice(0, tokens.length - 1).join(" ");
            }

            rows = rows.concat([{
                "row_id": next_id,
                "name": item_name,
                "quantity_text": qty_text,
                "unit": "PIECE"
            }]);
            next_id += 1;
        }
        return rows;
    }

    def stage_from_text() -> None {
        parsed_rows = parse_receipt_output(extracted_text);
        status_text = ["Parsed ", String(parsed_rows.length), " items from text."].join("");
    }

    def add_empty_item_row() -> None {
        next_id = parsed_rows.length + 1;
        parsed_rows = parsed_rows.concat([{
            "row_id": next_id,
            "name": "",
            "quantity_text": "1",
            "unit": "PIECE"
        }]);
    }

    def on_receipt_file_change(e: any) -> None {
        files = e.target.files;
        if not files or files.length == 0 {
            receipt_file_name = "";
            receipt_image_b64 = "";
            return;
        }

        file = files[0];
        receipt_file_name = file.name;
        if file.type and file.type.trim() {
            receipt_image_mime_type = file.type;
        } else {
            receipt_image_mime_type = "image/jpeg";
        }

        reader = Reflect.construct(FileReader, []);
        reader.onload = lambda ev: any -> None {
            raw_data_url = ev.target.result;
            receipt_image_b64 = raw_data_url.split(",")[1];
            status_text = "Receipt image loaded. Click Parse Receipt (API).";
        };
        reader.onerror = lambda _ev: any -> None {
            status_text = "Failed to read receipt file.";
        };
        reader.readAsDataURL(file);
    }

    async def parse_receipt_api() -> None {
        if not receipt_image_b64 and not extracted_text.trim() {
            status_text = "Provide either an image upload or receipt text to parse.";
            return;
        }

        loading = true;
        status_text = "Parsing receipt with API...";
        try {
            result = {};
            if receipt_image_b64 {
                result = root spawn ParseReceiptImageToPantry(
                    image_base64=receipt_image_b64,
                    image_mime_type=receipt_image_mime_type
                );
            } else {
                result = root spawn ParseReceiptTextToPantry(receipt_text=extracted_text);
            }

            out = first_report_payload(result);
            receipt_parse_payload = out;

            if out.ok == false {
                status_text = "Receipt parse failed: " + String(out.error or "unknown error");
                loading = false;
                return;
            }

            if out.extracted_text and String(out.extracted_text).trim() {
                extracted_text = String(out.extracted_text);
            }

            stage_rows_from_items(out.items or []);
            status_text = ["API parsed ", String(parsed_rows.length), " items. Edit item name, quantity, and measurement."].join("");
        } except Exception as e {
            status_text = "Receipt parse failed: " + e.toString();
        }
        loading = false;
    }

    def update_row_name(row_id: int, value: str) -> None {
        next_rows: list = [];
        for row in parsed_rows {
            if row.row_id == row_id {
                next_rows = next_rows.concat([{
                    "row_id": row.row_id,
                    "name": value,
                    "quantity_text": row.quantity_text,
                    "unit": row.unit
                }]);
            } else {
                next_rows = next_rows.concat([row]);
            }
        }
        parsed_rows = next_rows;
    }

    def update_row_qty(row_id: int, value: str) -> None {
        next_rows: list = [];
        for row in parsed_rows {
            if row.row_id == row_id {
                next_rows = next_rows.concat([{
                    "row_id": row.row_id,
                    "name": row.name,
                    "quantity_text": value,
                    "unit": row.unit
                }]);
            } else {
                next_rows = next_rows.concat([row]);
            }
        }
        parsed_rows = next_rows;
    }

    def update_row_unit(row_id: int, value: str) -> None {
        next_rows: list = [];
        for row in parsed_rows {
            if row.row_id == row_id {
                next_rows = next_rows.concat([{
                    "row_id": row.row_id,
                    "name": row.name,
                    "quantity_text": row.quantity_text,
                    "unit": normalize_unit(value)
                }]);
            } else {
                next_rows = next_rows.concat([row]);
            }
        }
        parsed_rows = next_rows;
    }

    def remove_row(row_id: int) -> None {
        parsed_rows = parsed_rows.filter(
            lambda row: dict -> bool { return row.row_id != row_id; }
        );
    }

    def add_to_pantry() -> None {
        staged: list = [];
        for row in parsed_rows {
            row_name = row.name.trim();
            if not row_name {
                continue;
            }
            staged = staged.concat([{
                "name": row_name,
                "quantity": row.quantity_text.trim(),
                "unit": normalize_unit(row.unit)
            }]);
        }

        if staged.length == 0 {
            status_text = "No valid items to add.";
            return;
        }

        pantry_items = pantry_items.concat(staged);
        status_text = ["Added ", String(staged.length), " items to pantry list."].join("");
    }

    return
        <div
            style={{
                "background": "#ffffffde",
                "border": "1px solid #d2e3f5",
                "borderRadius": "18px",
                "padding": "18px",
                "display": "grid",
                "gap": "14px"
            }}
        >
            <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "gap": "12px", "flexWrap": "wrap"}}>
                <div>
                    <h2 style={{"margin": "0"}}>Receipt Upload</h2>
                    <p style={{"margin": "6px 0 0 0", "opacity": "0.76"}}>
                        Extracted receipt items are listed item-by-item and fully editable.
                    </p>
                </div>
                <div style={{"background": "#eff6ff", "border": "1px solid #bfdbfe", "borderRadius": "10px", "padding": "8px 10px", "fontWeight": "700"}}>
                    {receipt_file_name if receipt_file_name else "No file chosen"}
                </div>
            </div>

            <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                {[( "Working... " if loading else "Ready. " ), status_text].join("")}
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "minmax(0, 1fr) minmax(0, 1fr)", "gap": "12px"}}>
                <div style={{"display": "grid", "gap": "10px"}}>
                    <label style={{"fontWeight": "700"}}>1) Upload Receipt</label>
                    <input type="file" accept="image/*" onChange={on_receipt_file_change} />
                    <label style={{"fontWeight": "700"}}>2) Raw OCR Text (optional / editable)</label>
                    <textarea
                        value={extracted_text}
                        onChange={lambda e: any -> None { extracted_text = e.target.value; }}
                        style={{"minHeight": "120px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "padding": "10px"}}
                    />
                    <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                        <button
                            onClick={parse_receipt_api}
                            style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": "#dbeafe", "fontWeight": "700"}}
                        >
                            Parse Receipt (API)
                        </button>
                        <button
                            onClick={stage_from_text}
                            style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #7c3aed", "background": "#ede9fe", "fontWeight": "700"}}
                        >
                            Parse From Raw Text
                        </button>
                    </div>
                </div>

                <div style={{"background": "#f8fbff", "border": "1px dashed #c7d8ef", "borderRadius": "12px", "padding": "10px", "display": "grid", "gap": "8px"}}>
                    <h3 style={{"margin": "0"}}>Latest Parse Payload</h3>
                    <pre style={{"margin": "0", "background": "#0f172a", "color": "#e2e8f0", "borderRadius": "10px", "padding": "10px", "overflowX": "auto", "maxHeight": "220px", "overflowY": "auto"}}>{JSON.stringify(receipt_parse_payload, None, 2)}</pre>
                    <button
                        onClick={add_to_pantry}
                        style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #0f766e", "background": "#ccfbf1", "fontWeight": "700", "width": "fit-content"}}
                    >
                        Add Items To Pantry
                    </button>
                </div>
            </div>

            <div style={{"display": "grid", "gap": "10px"}}>
                <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "gap": "8px", "flexWrap": "wrap"}}>
                    <h3 style={{"margin": "0"}}>Extracted Items (Editable)</h3>
                    <button onClick={add_empty_item_row} style={{"padding": "7px 11px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": "#eff6ff", "fontWeight": "700"}}>Add Item Row</button>
                </div>

                {(
                    <div style={{"opacity": "0.75"}}>No extracted items yet. Parse receipt first or add rows manually.</div>
                ) if parsed_rows.length == 0 else (
                    <div style={{"display": "grid", "gap": "8px"}}>
                        {parsed_rows.map(
                            lambda row: dict -> JsxElement { return
                                <div key={row.row_id.toString()} style={{"display": "grid", "gridTemplateColumns": "minmax(0, 2fr) minmax(120px, 1fr) minmax(130px, 1fr) auto", "gap": "8px", "alignItems": "center", "padding": "10px", "border": "1px solid #e2e8f0", "borderRadius": "10px", "background": "#ffffff"}}>
                                    <input value={row.name} onChange={lambda e: any -> None { update_row_name(row.row_id, e.target.value); }} placeholder="Item name" />
                                    <input value={row.quantity_text} onChange={lambda e: any -> None { update_row_qty(row.row_id, e.target.value); }} placeholder="Qty" />
                                    <select value={row.unit} onChange={lambda e: any -> None { update_row_unit(row.row_id, e.target.value); }}>
                                        <option value="PIECE">PIECE</option>
                                        <option value="OZ">OZ</option>
                                        <option value="LB">LB</option>
                                    </select>
                                    <button onClick={lambda -> None { remove_row(row.row_id); }} style={{"border": "1px solid #fecaca", "background": "#fff1f2", "borderRadius": "8px", "padding": "6px 8px"}}>Remove</button>
                                </div>; }
                        )}
                    </div>
                )}
            </div>

            <div style={{"display": "grid", "gap": "8px"}}>
                <h3 style={{"margin": "0"}}>Pantry Preview</h3>
                {(
                    <div style={{"opacity": "0.75"}}>No pantry items added from receipts yet.</div>
                ) if pantry_items.length == 0 else (
                    <div style={{"display": "grid", "gap": "6px"}}>
                        {pantry_items.map(
                            lambda item: dict -> JsxElement { return
                                <div key={[item.name, item.unit, item.quantity].join("-")} style={{"display": "flex", "justifyContent": "space-between", "padding": "8px", "border": "1px solid #e2e8f0", "borderRadius": "10px", "background": "#f8fafc"}}>
                                    <span>{item.name}</span>
                                    <span>{[item.quantity, " ", item.unit].join("")}</span>
                                </div>; }
                        )}
                    </div>
                )}
            </div>
        </div>;
}
