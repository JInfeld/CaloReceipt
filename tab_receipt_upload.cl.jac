sv import from ingredient {
    ParseReceiptTextToPantry,
    ParseReceiptImageToPantry
}

def:pub ReceiptUploadTab(shared_state: dict = {}) -> JsxElement {
    has loading: bool = false;
    has status_text: str = "Upload a receipt image, parse it with API, review items, and add to pantry.";
    has ocr_last_duration_ms: int = 0;
    has ocr_timer_display: str = "Last OCR time: --";
    has request_counter: int = 0;
    has receipt_debug_events: list = [];

    has receipt_file_name: str = "";
    has receipt_image_b64: str = "";
    has receipt_image_mime_type: str = "image/jpeg";

    has extracted_text: str = "";
    has parsed_rows: list = [];
    has receipt_parse_payload: dict = {};

    def now_ms() -> int {
        now_obj = Reflect.construct(Date, []);
        return parseInt(now_obj.getTime().toString());
    }

    def format_elapsed_label(ms: int) -> str {
        sec_text = String((ms / 1000.0).toFixed(2));
        return sec_text.concat("s");
    }

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

    def norm_name(raw: any) -> str {
        return String(raw or "").trim().toLowerCase().split(" ").filter(
            lambda part: str -> bool { return part.trim().length > 0; }
        ).join(" ");
    }

    def qty_or_one(raw: any) -> float {
        parsed = parseFloat(String(raw or "1").trim());
        if isNaN(parsed) or parsed <= 0 {
            return 1.0;
        }
        return parsed;
    }

    def num_or_zero(raw: any) -> float {
        parsed = parseFloat(String(raw or "0").trim());
        if isNaN(parsed) {
            return 0.0;
        }
        return parsed;
    }

    def pantry_items_ref() -> list {
        if not shared_state.pantry_items {
            shared_state.pantry_items = [];
        }
        return shared_state.pantry_items;
    }

    def add_debug(event_name: str, payload: dict = {}) -> None {
        receipt_debug_events = ([{
            "ts_ms": now_ms(),
            "event": event_name,
            "payload": payload
        }]).concat(receipt_debug_events).slice(0, 80);
    }

    def reset_receipt_parse_state(clear_file: bool = False, clear_text: bool = False) -> None {
        if clear_text {
            extracted_text = "";
        }
        parsed_rows = [];
        receipt_parse_payload = {};
        if clear_file {
            receipt_file_name = "";
            receipt_image_b64 = "";
            receipt_image_mime_type = "image/jpeg";
        }
    }

    async def post_walker_with_timeout(walker_name: str, payload: dict) -> dict {
        resp = await fetch(
            "/walker/".concat(walker_name),
            {
                "method": "POST",
                "headers": {"Content-Type": "application/json"},
                "body": JSON.stringify(payload)
            }
        );
        if not resp.ok {
            return {
                "ok": False,
                "stage": "http",
                "error": ["HTTP ", String(resp.status), " ", walker_name].join("")
            };
        }
        return await resp.json();
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
        if loading {
            return;
        }
        if not receipt_image_b64 and not extracted_text.trim() {
            status_text = "Provide either an image upload or receipt text to parse.";
            return;
        }

        request_counter += 1;
        req_id = ["receipt-", String(now_ms()), "-", String(request_counter)].join("");
        loading = true;
        status_text = "Running OCR and parser...";
        text_input = extracted_text;
        reset_receipt_parse_state(False, False);
        add_debug("parse:start", {"request_id": req_id, "has_image": (receipt_image_b64 != ""), "has_text": (extracted_text.trim() != "")});
        started_at = now_ms();
        try {
            result = {};
            if receipt_image_b64 {
                status_text = "Running OCR...";
                result = await post_walker_with_timeout(
                    "ParseReceiptImageToPantry",
                    {
                        "image_base64": receipt_image_b64,
                        "image_mime_type": receipt_image_mime_type
                    }
                );
            } else {
                status_text = "Running parser...";
                result = await post_walker_with_timeout(
                    "ParseReceiptTextToPantry",
                    {"receipt_text": text_input}
                );
            }

            out = first_report_payload(result);
            receipt_parse_payload = out;
            add_debug("parse:response", {"request_id": req_id, "ok": out.ok, "stage": out.stage, "diagnostics": out.diagnostics});

            if out.ok == false {
                stage_name = String(out.stage or "pipeline");
                status_text = ["Receipt ", stage_name, " failed: ", String(out.error or "unknown error")].join("");
                loading = false;
                return;
            }

            if out.extracted_text and String(out.extracted_text).trim() {
                extracted_text = String(out.extracted_text);
            }

            stage_rows_from_items(out.items or []);
            ended_at = now_ms();
            elapsed_ms = ended_at - started_at;
            if elapsed_ms < 1 {
                elapsed_ms = 1;
            }
            try {
                if out.diagnostics and out.diagnostics.ocr_ms and out.diagnostics.ocr_ms > 0 {
                    ocr_last_duration_ms = parseInt(String(out.diagnostics.ocr_ms));
                } else {
                    ocr_last_duration_ms = elapsed_ms;
                }
            } except Exception as _e {
                ocr_last_duration_ms = elapsed_ms;
            }
            ocr_timer_display = ["Last OCR time: ", format_elapsed_label(ocr_last_duration_ms)].join("");
            status_text = ["API parsed ", String((out.items or []).length), " items. Edit item name, quantity, and measurement."].join("");
            add_debug("parse:success", {"request_id": req_id, "item_count": String((out.items or []).length), "ocr_ms": ocr_last_duration_ms});
        } except Exception as e {
            err_text = e.toString();
            if String(err_text).includes("AbortError") {
                status_text = "Receipt parse timed out. Try again or use Parse From Raw Text.";
            } else {
                status_text = "Receipt parse failed: " + err_text;
            }
            add_debug("parse:error", {"request_id": req_id, "error": err_text});
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

        merged: list = pantry_items_ref();
        for incoming in staged {
            in_name = String(incoming.name or "").trim();
            in_unit = normalize_unit(String(incoming.unit or "PIECE"));
            next_merged: list = [];
            found = false;
            for cur in merged {
                cur_name = String(cur.name or "").trim();
                cur_unit = normalize_unit(String(cur.unit or "PIECE"));
                if norm_name(cur_name) == norm_name(in_name) and cur_unit == in_unit {
                    next_merged = next_merged.concat([{
                        "name": in_name,
                        "quantity": qty_or_one(cur.quantity) + qty_or_one(incoming.quantity),
                        "unit": in_unit,
                        "cost": num_or_zero(cur.cost) + num_or_zero(incoming.cost),
                        "protein": num_or_zero(cur.protein) + num_or_zero(incoming.protein),
                        "carb": num_or_zero(cur.carb) + num_or_zero(incoming.carb),
                        "fat": num_or_zero(cur.fat) + num_or_zero(incoming.fat)
                    }]);
                    found = true;
                } else {
                    next_merged = next_merged.concat([cur]);
                }
            }
            if not found {
                next_merged = next_merged.concat([{
                    "name": in_name,
                    "quantity": qty_or_one(incoming.quantity),
                    "unit": in_unit,
                    "cost": num_or_zero(incoming.cost),
                    "protein": num_or_zero(incoming.protein),
                    "carb": num_or_zero(incoming.carb),
                    "fat": num_or_zero(incoming.fat)
                }]);
            }
            merged = next_merged;
        }
        shared_state.pantry_items = merged;
        reset_receipt_parse_state(True, True);
        status_text = ["Added ", String(staged.length), " items to pantry list. Upload next receipt."].join("");
        add_debug("pantry:add", {"added_count": String(staged.length), "pantry_size": String(pantry_items_ref().length)});
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
            <div style={{"fontWeight": "600"}}>{ocr_timer_display}</div>

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
                            disabled={loading}
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
                        disabled={loading}
                        style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #0f766e", "background": "#ccfbf1", "fontWeight": "700", "width": "fit-content"}}
                    >
                        Add Items To Pantry
                    </button>
                </div>
            </div>

            <div style={{"background": "#fff7ed", "border": "1px solid #fdba74", "borderRadius": "12px", "padding": "10px"}}>
                <h3 style={{"margin": "0 0 8px 0"}}>Receipt Debug (latest 80)</h3>
                <pre style={{"margin": "0", "background": "#111827", "color": "#fde68a", "borderRadius": "10px", "padding": "10px", "overflowX": "auto", "maxHeight": "180px", "overflowY": "auto"}}>
                    {JSON.stringify(receipt_debug_events, None, 2)}
                </pre>
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
                ) if pantry_items_ref().length == 0 else (
                    <div style={{"display": "grid", "gap": "6px"}}>
                        {pantry_items_ref().map(
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
