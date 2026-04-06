sv import from ingredient {
    ParseReceiptTextToPantry,
    ParseReceiptImageToPantry
}

def:pub ReceiptUploadTab(
    shared_state: dict = {},
    on_auth_error: any = None,
    on_pantry_change: any = None,
    is_active: bool = true
) -> JsxElement {
    has loading: bool = false;
    has status_text: str = "Upload a receipt or paste the items, review the results, and add them to your pantry.";
    has ocr_last_duration_ms: int = 0;
    has ocr_timer_display: str = "Last scan: --";

    has receipt_file_name: str = "";
    has receipt_image_b64: str = "";
    has receipt_image_preview_url: str = "";
    has receipt_image_mime_type: str = "image/jpeg";
    has camera_stream: any = None;
    has camera_open: bool = false;
    has camera_starting: bool = false;
    has camera_error_text: str = "";

    has extracted_text: str = "";
    has parsed_rows: list = [];
    has parse_source_display: str = "Parser: --";
    has usda_lookup_display: str = "USDA lookup: --";
    has usda_matched_count: int = 0;
    has usda_unresolved_count: int = 0;

    def now_ms() -> int {
        now_obj = Reflect.construct(Date, []);
        return parseInt(now_obj.getTime().toString());
    }

    def format_elapsed_label(ms: int) -> str {
        sec_text = String((ms / 1000.0).toFixed(2));
        return sec_text.concat("s");
    }

    def camera_video_id() -> str {
        return "receipt-camera-video";
    }

    def camera_canvas_id() -> str {
        return "receipt-camera-canvas";
    }

    def camera_video_el() -> any {
        try {
            return window.document.getElementById(camera_video_id());
        } except Exception as _e {
            return None;
        }
    }

    def camera_canvas_el() -> any {
        try {
            return window.document.getElementById(camera_canvas_id());
        } except Exception as _e {
            return None;
        }
    }

    def in_app_camera_supported() -> bool {
        try {
            return (
                window.navigator and
                window.navigator.mediaDevices and
                window.navigator.mediaDevices.getUserMedia
            );
        } except Exception as _e {
            return false;
        }
    }

    def has_receipt_preview() -> bool {
        return String(receipt_image_preview_url or "").trim().length > 0;
    }

    def stop_camera_stream() -> None {
        if camera_stream and camera_stream.getTracks {
            try {
                tracks = camera_stream.getTracks();
                for track in tracks {
                    track.stop();
                }
            } except Exception as _e {
                0;
            }
        }
        camera_stream = None;
        video_el = camera_video_el();
        if video_el {
            try {
                video_el.pause();
            } except Exception as _e {
                0;
            }
            try {
                video_el.srcObject = None;
            } except Exception as _e {
                0;
            }
        }
    }

    def close_camera() -> None {
        stop_camera_stream();
        camera_open = false;
        camera_starting = false;
    }

    def first_report_payload(raw_result: dict) -> dict {
        if not raw_result {
            return {};
        }
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

    def is_auth_error_text(text: str) -> bool {
        lower = String(text or "").toLowerCase();
        return (
            lower.includes("401") or
            lower.includes("unauthorized") or
            lower.includes("forbidden") or
            lower.includes("token") or
            lower.includes("auth")
        );
    }

    def maybe_trigger_auth_error(text: str) -> None {
        if on_auth_error and is_auth_error_text(text) {
            0;
        }
    }

    def is_listish(raw: any) -> bool {
        if not raw {
            return false;
        }
        if Array.isArray(raw) {
            return true;
        }
        try {
            raw_len = parseInt(String(raw.length));
            if isNaN(raw_len) or raw_len < 0 {
                return false;
            }
            probe = raw.map(lambda item: any -> any : item);
            if Array.isArray(probe) {
                return true;
            }
        } except Exception as _e {
            0;
        }
        return false;
    }

    def normalize_unit(raw: str) -> str {
        text = String(raw).trim().toUpperCase();
        if text == "LOAF" {
            return "LOAF";
        }
        if text == "LB" {
            return "LB";
        }
        if text == "OZ" {
            return "OZ";
        }
        if text == "CUP" {
            return "CUP";
        }
        if text == "TBSP" {
            return "TBSP";
        }
        if text == "TSP" {
            return "TSP";
        }
        if text == "CLOVE" {
            return "CLOVE";
        }
        if text == "BUNCH" {
            return "BUNCH";
        }
        return "PIECE";
    }

    def serving_size_display(item: any) -> str {
        serving_text = String(item.serving_size or "").trim();
        if serving_text.length > 0 {
            return serving_text;
        }
        unit_text = normalize_unit(String(item.unit or "PIECE"));
        if unit_text == "PIECE" {
            return "1 piece";
        }
        if unit_text == "LOAF" {
            return "1 loaf";
        }
        if unit_text == "TBSP" {
            return "1 tbsp";
        }
        if unit_text == "TSP" {
            return "1 tsp";
        }
        if unit_text == "CUP" {
            return "1 cup";
        }
        if unit_text == "CLOVE" {
            return "1 clove";
        }
        if unit_text == "BUNCH" {
            return "1 bunch";
        }
        if unit_text == "OZ" {
            return "1 oz";
        }
        if unit_text == "LB" {
            return "1 lb";
        }
        return "";
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

    def total_quantity_value(raw_qty: any, fallback_qty: any = 0.0) -> float {
        qty_value = num_or_zero(raw_qty);
        if qty_value > 0.0 {
            return qty_value;
        }
        return num_or_zero(fallback_qty);
    }

    def total_quantity_display(item: any) -> str {
        display_qty = total_quantity_value(item.package_quantity, item.quantity);
        display_unit = normalize_unit(String(item.package_unit or item.unit or "PIECE"));
        if display_qty <= 0.0 {
            display_qty = 1.0;
        }
        return [String(display_qty), " ", display_unit].join("");
    }

    def count_or_zero(raw: any) -> int {
        parsed = parseInt(String(raw or "0"));
        if isNaN(parsed) or parsed < 0 {
            return 0;
        }
        return parsed;
    }

    def format_macro_value(raw: any) -> str {
        return String((num_or_zero(raw)).toFixed(1));
    }

    def nutrition_summary_text(item: any) -> str {
        serving_text = String(item.serving_size or "").trim();
        protein_value = num_or_zero(item.protein);
        carb_value = num_or_zero(item.carb);
        fat_value = num_or_zero(item.fat);
        has_macros = protein_value > 0.0 or carb_value > 0.0 or fat_value > 0.0;
        if serving_text.length == 0 and not has_macros {
            return "";
        }

        macro_text = "";
        if has_macros {
            macro_text = [
                "Protein ",
                format_macro_value(protein_value),
                "g | Carbs ",
                format_macro_value(carb_value),
                "g | Fat ",
                format_macro_value(fat_value),
                "g"
            ].join("");
        }
        if serving_text.length > 0 and macro_text != "" {
            return ["Serving ", serving_text, " | ", macro_text].join("");
        }
        if serving_text.length > 0 {
            return "Serving ".concat(serving_text);
        }
        return macro_text;
    }

    def parse_stage_display(raw_stage: any, used_image_scan: bool) -> str {
        if not used_image_scan {
            return "Parser: Typed Receipt LLM";
        }
        stage_text = String(raw_stage or "").trim().toLowerCase();
        if stage_text == "llm_pipeline" {
            return "Parser: OCR Pipeline LLM";
        }
        if stage_text == "llm_image" {
            return "Parser: Image LLM";
        }
        if stage_text == "llm_text" {
            return "Parser: OCR Text LLM Fallback";
        }
        if stage_text == "llm_fallback" {
            return "Parser: Basic OCR Fallback";
        }
        return "Parser: Receipt LLM";
    }

    def usda_lookup_summary(raw_lookup: any, item_count: int) -> str {
        if item_count <= 0 {
            return "USDA lookup: --";
        }

        matched_count = 0;
        unresolved_count = 0;
        if raw_lookup {
            matched_count = count_or_zero(raw_lookup.matched_count);
            unresolved_count = count_or_zero(raw_lookup.unresolved_count);
        }

        if matched_count <= 0 and unresolved_count <= 0 {
            return "USDA lookup: no direct match data returned yet";
        }
        if unresolved_count > 0 {
            return ["USDA lookup: matched ", String(matched_count), "/", String(item_count), " | review ", String(unresolved_count)].join("");
        }
        return ["USDA lookup: matched ", String(matched_count), "/", String(item_count)].join("");
    }

    def reset_scan_feedback() -> None {
        parse_source_display = "Parser: --";
        usda_lookup_display = "USDA lookup: --";
        usda_matched_count = 0;
        usda_unresolved_count = 0;
    }

    def per_serving_merge_value(left_value: any, left_qty: float, right_value: any, right_qty: float) -> float {
        total_qty = left_qty + right_qty;
        if total_qty <= 0.0 {
            return 0.0;
        }
        return (
            (num_or_zero(left_value) * left_qty) +
            (num_or_zero(right_value) * right_qty)
        ) / total_qty;
    }

    def receipt_row_payload(
        row_id: int,
        name: str,
        quantity_text: str,
        unit: str,
        cost: any = 0.0,
        protein: any = 0.0,
        carb: any = 0.0,
        fat: any = 0.0,
        serving_size: any = "",
        storage_quantity: any = 0.0,
        storage_unit: any = "PIECE"
    ) -> dict {
        return {
            "row_id": row_id,
            "name": name,
            "quantity_text": quantity_text,
            "unit": normalize_unit(unit),
            "cost": num_or_zero(cost),
            "protein": num_or_zero(protein),
            "carb": num_or_zero(carb),
            "fat": num_or_zero(fat),
            "serving_size": String(serving_size or "").trim(),
            "storage_quantity": num_or_zero(storage_quantity),
            "storage_unit": normalize_unit(String(storage_unit or unit or "PIECE"))
        };
    }

    def pantry_items_ref() -> list {
        if not shared_state.pantry_items or not is_listish(shared_state.pantry_items) {
            shared_state.pantry_items = [];
        }
        return shared_state.pantry_items;
    }

    async def set_pantry_items(items: list) -> None {
        shared_state.pantry_items = items;
        if on_pantry_change {
            await on_pantry_change(items);
        }
    }

    def reset_receipt_parse_state(clear_file: bool = False, clear_text: bool = False) -> None {
        if clear_text {
            extracted_text = "";
        }
        parsed_rows = [];
        reset_scan_feedback();
        if clear_file {
            close_camera();
            receipt_file_name = "";
            receipt_image_b64 = "";
            receipt_image_preview_url = "";
            receipt_image_mime_type = "image/jpeg";
            camera_error_text = "";
        }
    }

    async def post_walker_with_timeout(walker_name: str, payload: dict) -> dict {
        resp = await fetch(
            "/walker/".concat(walker_name),
            {
                "method": "POST",
                "headers": {"Content-Type": "application/json"},
                "credentials": "include",
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
            rows = rows.concat([receipt_row_payload(
                row_id,
                item_name,
                String(item.package_quantity or item.quantity or 1),
                String(item.package_unit or item.unit or "PIECE"),
                item.cost,
                item.protein,
                item.carb,
                item.fat,
                item.serving_size,
                item.quantity,
                item.unit
            )]);
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

            rows = rows.concat([receipt_row_payload(next_id, item_name, qty_text, "PIECE")]);
            next_id += 1;
        }
        return rows;
    }

    def stage_from_text() -> None {
        parsed_rows = parse_receipt_output(extracted_text);
        parse_source_display = "Parser: Manual Typed List";
        usda_lookup_display = "USDA lookup: skipped for manual typed list";
        usda_matched_count = 0;
        usda_unresolved_count = 0;
        status_text = ["Parsed ", String(parsed_rows.length), " items from the text you entered."].join("");
    }

    def intake_state_label() -> str {
        if has_receipt_preview() {
            return "Photo Ready";
        }
        if extracted_text.trim() {
            return "Typed Receipt Ready";
        }
        return "Waiting For Receipt";
    }

    def add_empty_item_row() -> None {
        next_id = parsed_rows.length + 1;
        parsed_rows = parsed_rows.concat([receipt_row_payload(next_id, "", "1", "PIECE")]);
    }

    async def start_camera() -> None {
        if camera_starting {
            return;
        }
        if not in_app_camera_supported() {
            camera_error_text = "In-app camera is not available in this browser. Upload a photo instead.";
            status_text = camera_error_text;
            return;
        }

        camera_error_text = "";
        camera_starting = true;
        camera_open = true;
        stop_camera_stream();
        status_text = "Requesting camera access...";
        try {
            stream = await window.navigator.mediaDevices.getUserMedia(
                {
                    "video": {
                        "facingMode": {"ideal": "environment"},
                        "width": {"ideal": 1920},
                        "height": {"ideal": 1080}
                    },
                    "audio": false
                }
            );
            camera_stream = stream;
            video_el = camera_video_el();
            if not video_el {
                close_camera();
                camera_error_text = "Camera preview could not be initialized.";
                status_text = camera_error_text;
                return;
            }
            video_el.srcObject = stream;
            try {
                await video_el.play();
            } except Exception as _e {
                0;
            }
            camera_starting = false;
            status_text = "Camera live. Hold the receipt inside the frame and tap Take Photo.";
        } except Exception as e {
            close_camera();
            camera_error_text = "Camera access failed: " + e.toString();
            status_text = camera_error_text;
        }
    }

    def capture_camera_photo() -> None {
        if not camera_open {
            status_text = "Open the camera before taking a photo.";
            return;
        }
        video_el = camera_video_el();
        canvas_el = camera_canvas_el();
        if not video_el or not canvas_el {
            status_text = "Camera capture surface is unavailable.";
            return;
        }
        frame_width = parseInt(String(video_el.videoWidth or 0));
        frame_height = parseInt(String(video_el.videoHeight or 0));
        if isNaN(frame_width) or isNaN(frame_height) or frame_width < 1 or frame_height < 1 {
            status_text = "Camera is still warming up. Try again in a moment.";
            return;
        }

        canvas_el.width = frame_width;
        canvas_el.height = frame_height;
        draw_ctx = canvas_el.getContext("2d");
        if not draw_ctx {
            status_text = "Camera capture failed.";
            return;
        }
        draw_ctx.drawImage(video_el, 0, 0, frame_width, frame_height);
        data_url = canvas_el.toDataURL("image/jpeg", 0.92);
        receipt_image_preview_url = data_url;
        receipt_image_b64 = data_url.split(",")[1];
        receipt_image_mime_type = "image/jpeg";
        receipt_file_name = ["receipt-camera-", String(now_ms()), ".jpg"].join("");
        camera_error_text = "";
        close_camera();
        status_text = "Receipt photo captured. Click Parse Receipt (API).";
    }

    def clear_loaded_receipt_image() -> None {
        close_camera();
        receipt_file_name = "";
        receipt_image_b64 = "";
        receipt_image_preview_url = "";
        receipt_image_mime_type = "image/jpeg";
        camera_error_text = "";
        status_text = "Receipt image cleared.";
    }

    def on_receipt_file_change(e: any) -> None {
        files = e.target.files;
        if not files or files.length == 0 {
            return;
        }

        close_camera();
        camera_error_text = "";
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
            receipt_image_preview_url = raw_data_url;
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
            status_text = "Add a receipt photo or type the items before scanning.";
            return;
        }

        loading = true;
        status_text = "Scanning your receipt...";
        text_input = extracted_text;
        reset_receipt_parse_state(False, False);
        started_at = now_ms();
        try {
            result = {};
            if receipt_image_b64 {
                status_text = "Reading the receipt photo...";
                result = await post_walker_with_timeout(
                    "ParseReceiptImageToPantry",
                    {
                        "image_base64": receipt_image_b64,
                        "image_mime_type": receipt_image_mime_type
                    }
                );
            } else {
                status_text = "Parsing the typed receipt...";
                result = await post_walker_with_timeout(
                    "ParseReceiptTextToPantry",
                    {"receipt_text": text_input}
                );
            }

            out = first_report_payload(result);

            if out.ok == false {
                stage_name = String(out.stage or "pipeline");
                status_text = ["Receipt ", stage_name, " failed: ", String(out.error or "unknown error")].join("");
                maybe_trigger_auth_error(String(out.error or ""));
                loading = false;
                return;
            }

            if out.extracted_text and String(out.extracted_text).trim() {
                extracted_text = String(out.extracted_text);
            }

            parsed_items = out.items or [];
            item_count = parsed_items.length;
            stage_rows_from_items(parsed_items);
            parse_source_display = parse_stage_display(out.stage, receipt_image_b64 != "");
            matched_count = 0;
            unresolved_count = 0;
            if out.nutrition_lookup {
                matched_count = count_or_zero(out.nutrition_lookup.matched_count);
                unresolved_count = count_or_zero(out.nutrition_lookup.unresolved_count);
            }
            usda_matched_count = matched_count;
            usda_unresolved_count = unresolved_count;
            usda_lookup_display = usda_lookup_summary(out.nutrition_lookup, item_count);
            ended_at = now_ms();
            elapsed_ms = ended_at - started_at;
            if elapsed_ms < 1 {
                elapsed_ms = 1;
            }
            resolved_duration_ms = elapsed_ms;
            try {
                if out.diagnostics and out.diagnostics.ocr_ms and out.diagnostics.ocr_ms > 0 {
                    resolved_duration_ms = parseInt(String(out.diagnostics.ocr_ms));
                }
            } except Exception as _e {
                resolved_duration_ms = elapsed_ms;
            }
            ocr_last_duration_ms = resolved_duration_ms;
            ocr_timer_display = ["Last scan: ", format_elapsed_label(resolved_duration_ms)].join("");
            next_status_text = "";
            if String(out.stage or "") == "llm_fallback" {
                next_status_text = ["We found ", String(item_count), " items using the emergency OCR fallback. Review every item, quantity, and unit carefully before saving."].join("");
            } elif (receipt_image_b64 != "") and String(out.stage or "") == "llm_text" {
                next_status_text = ["We found ", String(item_count), " items from OCR text parsing. Review the item names and quantities carefully before saving."].join("");
            } else {
                next_status_text = ["We found ", String(item_count), " items. Review names and quantities, then add them to your pantry."].join("");
            }
            if matched_count > 0 {
                next_status_text = [next_status_text, " USDA matched ", String(matched_count), "/", String(item_count), " items."].join("");
            } elif item_count > 0 {
                next_status_text = [next_status_text, " USDA nutrition still needs review for some items."].join("");
            }
            if unresolved_count > 0 {
                next_status_text = [next_status_text, " ", String(unresolved_count), " item(s) did not get a direct USDA match."].join("");
            }
            status_text = next_status_text;
        } except Exception as e {
            err_text = e.toString();
            if String(err_text).includes("AbortError") {
                status_text = "Receipt scan timed out. Try again or use the typed receipt option.";
            } else {
                status_text = "Receipt scan failed: " + err_text;
            }
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    def update_row_name(row_id: int, value: str) -> None {
        next_rows: list = [];
        for row in parsed_rows {
            if row.row_id == row_id {
                next_rows = next_rows.concat([receipt_row_payload(
                    row.row_id,
                    value,
                    row.quantity_text,
                    row.unit,
                    row.cost,
                    row.protein,
                    row.carb,
                    row.fat,
                    row.serving_size,
                    row.storage_quantity,
                    row.storage_unit
                )]);
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
                prior_display_qty = num_or_zero(row.quantity_text);
                next_display_qty = num_or_zero(value);
                next_storage_qty = num_or_zero(row.storage_quantity);
                if next_storage_qty <= 0.0 {
                    next_storage_qty = qty_or_one(row.quantity_text);
                }
                if prior_display_qty > 0.0 and next_display_qty > 0.0 {
                    next_storage_qty = next_storage_qty * (next_display_qty / prior_display_qty);
                }
                next_rows = next_rows.concat([receipt_row_payload(
                    row.row_id,
                    row.name,
                    value,
                    row.unit,
                    row.cost,
                    row.protein,
                    row.carb,
                    row.fat,
                    row.serving_size,
                    next_storage_qty,
                    row.storage_unit
                )]);
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
                next_rows = next_rows.concat([receipt_row_payload(
                    row.row_id,
                    row.name,
                    row.quantity_text,
                    value,
                    row.cost,
                    row.protein,
                    row.carb,
                    row.fat,
                    row.serving_size,
                    row.storage_quantity,
                    row.storage_unit
                )]);
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

    async def add_to_pantry() -> None {
        staged: list = [];
        for row in parsed_rows {
            row_name = row.name.trim();
            if not row_name {
                continue;
            }
            staged = staged.concat([{
                "name": row_name,
                "quantity": (
                    row.storage_quantity
                    if num_or_zero(row.storage_quantity) > 0.0
                    else qty_or_one(row.quantity_text)
                ),
                "unit": (
                    normalize_unit(String(row.storage_unit or "PIECE"))
                    if String(row.storage_unit or "").trim().length > 0
                    else normalize_unit(row.unit)
                ),
                "cost": num_or_zero(row.cost),
                "protein": num_or_zero(row.protein),
                "carb": num_or_zero(row.carb),
                "fat": num_or_zero(row.fat),
                "serving_size": String(row.serving_size or "").trim(),
                "package_quantity": qty_or_one(row.quantity_text),
                "package_unit": normalize_unit(row.unit)
            }]);
        }

        if staged.length == 0 {
            status_text = "No valid items to add.";
            return;
        }

        merged: list = pantry_items_ref().slice();
        for incoming in staged {
            in_name = String(incoming.name or "").trim();
            in_unit = normalize_unit(String(incoming.unit or "PIECE"));
            in_serving_size = String(incoming.serving_size or "").trim();
            in_package_unit = normalize_unit(String(incoming.package_unit or incoming.unit or "PIECE"));
            next_merged: list = [];
            found = false;
            for cur in merged {
                cur_name = String(cur.name or "").trim();
                cur_unit = normalize_unit(String(cur.unit or "PIECE"));
                cur_serving_size = String(cur.serving_size or "").trim();
                cur_package_unit = normalize_unit(String(cur.package_unit or cur.unit or "PIECE"));
                if norm_name(cur_name) == norm_name(in_name) and cur_unit == in_unit and cur_serving_size == in_serving_size and cur_package_unit == in_package_unit {
                    cur_qty = qty_or_one(cur.quantity);
                    incoming_qty = qty_or_one(incoming.quantity);
                    total_qty = cur_qty + incoming_qty;
                    cur_package_qty = total_quantity_value(cur.package_quantity, cur.quantity);
                    incoming_package_qty = total_quantity_value(incoming.package_quantity, incoming.quantity);
                    next_merged = next_merged.concat([{
                        "name": in_name,
                        "quantity": total_qty,
                        "unit": in_unit,
                        "cost": per_serving_merge_value(cur.cost, cur_qty, incoming.cost, incoming_qty),
                        "protein": per_serving_merge_value(cur.protein, cur_qty, incoming.protein, incoming_qty),
                        "carb": per_serving_merge_value(cur.carb, cur_qty, incoming.carb, incoming_qty),
                        "fat": per_serving_merge_value(cur.fat, cur_qty, incoming.fat, incoming_qty),
                        "serving_size": in_serving_size,
                        "package_quantity": cur_package_qty + incoming_package_qty,
                        "package_unit": in_package_unit
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
                    "fat": num_or_zero(incoming.fat),
                    "serving_size": in_serving_size,
                    "package_quantity": total_quantity_value(incoming.package_quantity, incoming.quantity),
                    "package_unit": in_package_unit
                }]);
            }
            merged = next_merged;
        }

        previous_rows = parsed_rows.slice();
        previous_text = extracted_text;
        previous_file_name = receipt_file_name;
        previous_image_b64 = receipt_image_b64;
        previous_preview_url = receipt_image_preview_url;
        previous_image_mime_type = receipt_image_mime_type;
        previous_camera_error = camera_error_text;
        previous_parse_source = parse_source_display;
        previous_lookup_display = usda_lookup_display;
        previous_lookup_matched = usda_matched_count;
        previous_lookup_unresolved = usda_unresolved_count;

        reset_receipt_parse_state(True, True);
        status_text = "Adding items to pantry...";
        try {
            await set_pantry_items(merged);
            status_text = ["Added ", String(staged.length), " items to your pantry. You can upload another receipt whenever you're ready."].join("");
        } except Exception as e {
            parsed_rows = previous_rows;
            extracted_text = previous_text;
            receipt_file_name = previous_file_name;
            receipt_image_b64 = previous_image_b64;
            receipt_image_preview_url = previous_preview_url;
            receipt_image_mime_type = previous_image_mime_type;
            camera_error_text = previous_camera_error;
            parse_source_display = previous_parse_source;
            usda_lookup_display = previous_lookup_display;
            usda_matched_count = previous_lookup_matched;
            usda_unresolved_count = previous_lookup_unresolved;
            status_text = "Add to pantry failed: " + e.toString();
        }
    }

    can with [is_active] entry {
        if not is_active {
            close_camera();
        }
    }

    can with exit {
        close_camera();
    }

    return
        <div className="card cr-module-shell" style={{"display": "grid", "gap": "16px"}}>
            <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "gap": "12px", "flexWrap": "wrap"}}>
                <div>
                    <h2 style={{"margin": "0"}}>Receipt Upload</h2>
                    <p style={{"margin": "6px 0 0 0", "opacity": "0.76"}}>
                        Scan a grocery receipt, review the items we found, and add them to your pantry in one pass.
                    </p>
                </div>
                <div className="cr-chip info">
                    {receipt_file_name if receipt_file_name else intake_state_label()}
                </div>
            </div>

            <div className="receipt-summary-grid">
                <div className="stat-card">
                    <div className="stat-label">Receipt Input</div>
                    <div className="stat-value">{intake_state_label()}</div>
                    <div className="card-subtitle">
                        {("Ready to scan" if has_receipt_preview() or extracted_text.trim() else "Add a photo or type the receipt")}
                    </div>
                </div>
                <div className="stat-card">
                    <div className="stat-label">Items Ready</div>
                    <div className="stat-value">{String(parsed_rows.length)}</div>
                    <div className="card-subtitle">Review names and quantities before saving.</div>
                </div>
                <div className="stat-card">
                    <div className="stat-label">Pantry Items</div>
                    <div className="stat-value">{String(pantry_items_ref().length)}</div>
                    <div className="card-subtitle">Current ingredients already stored in your pantry.</div>
                </div>
                <div className="stat-card">
                    <div className="stat-label">USDA Lookup</div>
                    <div className="stat-value">
                        {([String(usda_matched_count), "/", String(parsed_rows.length)].join("") if parsed_rows.length > 0 else "--")}
                    </div>
                    <div className="card-subtitle">{usda_lookup_display}</div>
                </div>
            </div>

            <div className="cr-status info">
                {[( "Working... " if loading else "Ready. " ), status_text].join("")}
            </div>

            <div className="receipt-layout">
                <div className="card receipt-section-card">
                    <div className="card-header" style={{"marginBottom": "0"}}>
                        <div>
                            <div className="card-title">1. Capture Or Upload</div>
                            <div className="card-subtitle">Use the camera on mobile or upload a clear photo from desktop.</div>
                        </div>
                    </div>

                    <div className="receipt-preview-frame">
                        <video
                            id={camera_video_id()}
                            autoPlay={true}
                            playsInline={true}
                            muted={true}
                            style={{
                                "display": ("block" if camera_open else "none"),
                                "width": "100%",
                                "height": "100%",
                                "objectFit": "cover",
                                "minHeight": "340px",
                                "background": "#0f172a"
                            }}
                        />
                        <img
                            src={receipt_image_preview_url}
                            alt="Receipt preview"
                            style={{
                                "display": ("block" if (not camera_open) and has_receipt_preview() else "none"),
                                "width": "100%",
                                "height": "100%",
                                "objectFit": "cover",
                                "minHeight": "340px",
                                "background": "#0f172a"
                            }}
                        />
                        <div
                            className="receipt-preview-empty"
                            style={{"display": ("grid" if (not camera_open) and not has_receipt_preview() else "none")}}
                        >
                            <div className="receipt-preview-title">Receipt Camera</div>
                            <div className="receipt-preview-copy">
                                {("Open the camera and keep the full receipt inside the frame." if in_app_camera_supported() else "This browser does not support in-app camera access. Upload a receipt image instead.")}
                            </div>
                        </div>
                        <div className="receipt-preview-guides" />
                        <div className="receipt-preview-caption">
                            <div className="receipt-preview-pill">
                                {("Live Camera" if camera_open else ("Photo Ready" if has_receipt_preview() else "Awaiting Receipt"))}
                            </div>
                            <div className="receipt-preview-pill secondary">
                                {("Landscape photos work best for long receipts" if camera_open else "Upload works on desktop and mobile")}
                            </div>
                        </div>
                    </div>

                    <canvas id={camera_canvas_id()} style={{"display": "none"}} />

                    <div className="receipt-action-row">
                        <button onClick={start_camera} disabled={camera_starting} className="btn cr-btn-success">
                            {("Starting..." if camera_starting else ("Retake Photo" if has_receipt_preview() else "Open Camera"))}
                        </button>
                        <button onClick={capture_camera_photo} disabled={(not camera_open) or camera_starting} className="btn cr-btn-accent">
                            Take Photo
                        </button>
                        <button onClick={parse_receipt_api} disabled={loading or ((not receipt_image_b64) and (not extracted_text.trim()))} className="btn btn-secondary">
                            {("Scan Receipt" if receipt_image_b64 else "Scan Typed Receipt")}
                        </button>
                        <button onClick={clear_loaded_receipt_image} disabled={(not has_receipt_preview()) and (receipt_image_b64 == "")} className="btn cr-btn-danger">
                            Clear
                        </button>
                    </div>

                    <div className="receipt-upload-block">
                        <label className="form-label">Upload Instead</label>
                        <input type="file" accept="image/*" capture="environment" onChange={on_receipt_file_change} />
                        <div className="card-subtitle">
                            Upload a receipt screenshot or photo when using a laptop, or when the in-app camera is not ideal.
                        </div>
                    </div>

                    {(
                        <div className="cr-status warning">{camera_error_text}</div>
                    ) if camera_error_text else None}
                </div>

                <div className="receipt-side-stack">
                    <div className="card receipt-section-card">
                        <div className="card-header" style={{"marginBottom": "0"}}>
                            <div>
                                <div className="card-title">2. Type Receipt Instead</div>
                                <div className="card-subtitle">Useful when a photo is unavailable or you only want a quick manual entry.</div>
                            </div>
                        </div>
                        <textarea
                            value={extracted_text}
                            onChange={lambda e: any -> None { extracted_text = e.target.value; }}
                            placeholder={"Example:\nBananas 6\nGreek Yogurt 1\nSpinach 1"}
                            style={{"minHeight": "180px"}}
                        />
                        <div className="receipt-action-row">
                            <button onClick={parse_receipt_api} disabled={loading or ((not receipt_image_b64) and (not extracted_text.trim()))} className="btn cr-btn-accent">
                                Scan Typed Receipt
                            </button>
                            <button onClick={stage_from_text} disabled={extracted_text.trim().length == 0} className="btn btn-secondary">
                                Use Typed List
                            </button>
                        </div>
                    </div>

                    <div className="card receipt-section-card">
                        <div className="card-header" style={{"marginBottom": "0"}}>
                            <div>
                                <div className="card-title">Quick Tips</div>
                                <div className="card-subtitle">A cleaner scan usually means fewer edits.</div>
                            </div>
                        </div>
                        <div className="receipt-tips">
                            <div className="receipt-tip">Keep the whole receipt inside the frame and avoid cutting off the store header or bottom totals.</div>
                            <div className="receipt-tip">Flat lighting works best. Reduce shadows, glare, and wrinkles before taking the photo.</div>
                            <div className="receipt-tip">After scanning, edit item names and package quantities if anything looks off before saving.</div>
                        </div>
                        <div className="receipt-metric">
                            {ocr_timer_display}
                        </div>
                        <div className="card-subtitle">{parse_source_display}</div>
                    </div>
                </div>
            </div>

            <div className="card receipt-section-card">
                <div className="card-header">
                    <div>
                        <div className="card-title">3. Review Items</div>
                        <div className="card-subtitle">Make sure the item names and package quantities match your receipt before adding them.</div>
                    </div>
                    <div className="receipt-action-row">
                        <button onClick={add_empty_item_row} className="btn btn-secondary">Add Item</button>
                        <button onClick={add_to_pantry} disabled={loading or parsed_rows.length == 0} className="btn cr-btn-success">
                            Add Items To Pantry
                        </button>
                    </div>
                </div>

                {(
                    <div className="receipt-empty-state">
                        Scan a receipt or type in the items to start building your pantry update.
                    </div>
                ) if parsed_rows.length == 0 else (
                    <div className="receipt-editor-list">
                        {parsed_rows.map(
                            lambda row: dict -> JsxElement {
                                row_nutrition_text = nutrition_summary_text(row);
                                return
                                <div key={row.row_id.toString()} className="receipt-editor-row">
                                    <div className="receipt-editor-main">
                                        <div className="form-group">
                                            <label className="form-label">Item Name</label>
                                            <input value={row.name} onChange={lambda e: any -> None { update_row_name(row.row_id, e.target.value); }} placeholder="Item name" />
                                        </div>
                                        <div className="form-group">
                                            <label className="form-label">Package Quantity</label>
                                            <input value={row.quantity_text} onChange={lambda e: any -> None { update_row_qty(row.row_id, e.target.value); }} placeholder="Qty" />
                                        </div>
                                        <div className="form-group">
                                            <label className="form-label">Unit</label>
                                            <select value={row.unit} onChange={lambda e: any -> None { update_row_unit(row.row_id, e.target.value); }}>
                                                <option value="PIECE">PIECE</option>
                                                <option value="LOAF">LOAF</option>
                                                <option value="OZ">OZ</option>
                                                <option value="LB">LB</option>
                                                <option value="CUP">CUP</option>
                                                <option value="TBSP">TBSP</option>
                                                <option value="TSP">TSP</option>
                                                <option value="CLOVE">CLOVE</option>
                                                <option value="BUNCH">BUNCH</option>
                                            </select>
                                        </div>
                                        {(
                                            <div className="card-subtitle" style={{"gridColumn": "1 / -1"}}>
                                                {row_nutrition_text}
                                            </div>
                                        ) if row_nutrition_text.length > 0 else None}
                                    </div>
                                    <button onClick={lambda -> None { remove_row(row.row_id); }} className="btn cr-btn-danger">
                                        Remove
                                    </button>
                                </div>; }
                        )}
                    </div>
                )}
            </div>

            <div className="card receipt-section-card">
                <div className="card-header" style={{"marginBottom": "0"}}>
                    <div>
                        <div className="card-title">Pantry Preview</div>
                        <div className="card-subtitle">Your pantry stays cumulative, so repeat purchases are merged with existing items.</div>
                    </div>
                </div>
                {(
                    <div className="receipt-empty-state">
                        No pantry items yet. Once you add a receipt, your pantry preview will show up here.
                    </div>
                ) if pantry_items_ref().length == 0 else (
                    <div className="receipt-pantry-list">
                        {pantry_items_ref().map(
                            lambda item: dict -> JsxElement { return
                                <div key={[item.name, item.unit, item.quantity, String(item.serving_size or "")].join("-")} className="receipt-pantry-row">
                                    <span>{item.name}</span>
                                    <span>{[total_quantity_display(item), (" | serving " + serving_size_display(item)) if serving_size_display(item).length > 0 else ""].join("")}</span>
                                </div>; }
                        )}
                    </div>
                )}
            </div>
        </div>;
}
