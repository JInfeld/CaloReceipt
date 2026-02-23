sv import from user {
    SaveUserProfile,
    GetUserProfile,
    ClearUserProfile,
    GenerateUserMacroNeeds
}

sv import from ingredient {
    GenerateRecipeFromPantry,
    ListGeneratedRecipe,
    ClearGeneratedRecipe,
    ParseReceiptTextToPantry
}
sv import from receipt { ExtractReceiptText }

# Single-page test console for the full backend flow:
# create user -> persist user -> generate macros -> generate recipe -> update pantry.
def:pub app -> JsxElement {
    has status: str = "",
        loading: bool = false,
        user_profile: dict = {},
        macro_needs: dict = {},
        pantry: list = [],
        recipe: dict = {},
        receipt_parse: dict = {},
        last_error: dict = {},
        debug_events: list = [],
        show_debug: bool = true;

    has user_id: str = "",
        age: str = "",
        sex: str = "MALE",
        height: str = "",
        weight: str = "",
        dietary_restrictions_text: str = "",
        allergies_text: str = "",
        fitness_level: str = "MODERATELY_ACTIVE",
        goal: str = "MUSCLE_GAIN";

    has ing_name: str = "",
        ing_quantity: str = "1",
        ing_unit: str = "PIECE",
        ing_cost: str = "",
        ing_protein: str = "",
        ing_carb: str = "",
        ing_fat: str = "";

    has receipt_image_name: str = "",
        receipt_image_b64: str = "",
        receipt_processed_b64: str = "",
        receipt_image_mime_type: str = "image/jpeg",
        receipt_original_preview_url: str = "",
        receipt_processed_preview_url: str = "",
        receipt_ocr_text: str = "",
        pending_receipt_items: list = [];

    # Parse numeric text inputs safely to prevent NaN payloads.
    def to_num(value: str, fallback: float = 0.0) -> float {
        parsed = parseFloat(value);
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def is_int_str(value: str) -> bool {
        if not value.trim() {
            return false;
        }
        return not isNaN(parseInt(value));
    }

    def is_num_str(value: str) -> bool {
        if not value.trim() {
            return false;
        }
        return not isNaN(parseFloat(value));
    }

    def split_csv(text: str) -> list {
        if not text.trim() {
            return [];
        }
        return text.split(",").map(
            lambda item: str -> str { return item.trim(); }
        ).filter(
            lambda item: str -> bool { return item.length > 0; }
        );
    }

    # Handle Jac response envelope variants and return the first payload object.
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

    def has_parse_content(candidate: any) -> bool {
        if not candidate {
            return false;
        }
        try {
            if candidate.items and candidate.items.length >= 0 {
                return true;
            }
        } except Exception as _e {
            0;
        }
        if candidate.receipt_total != None {
            return true;
        }
        if candidate.extracted_text != None {
            return true;
        }
        return false;
    }

    def unwrap_parse_payload(parse_out: dict) -> dict {
        if parse_out.data and parse_out.data.result {
            nested = parse_out.data.result;
            if has_parse_content(nested) {
                return nested;
            }
        }
        if parse_out.result {
            nested = parse_out.result;
            if has_parse_content(nested) {
                return nested;
            }
        }
        if has_parse_content(parse_out) {
            return parse_out;
        }
        if parse_out.data and parse_out.data.result {
            return parse_out.data.result;
        }
        if parse_out.result {
            return parse_out.result;
        }
        return parse_out;
    }

    def normalize_unit_value(raw_unit: any) -> str {
        unit_text = "";
        try {
            unit_text = String(raw_unit).trim().toUpperCase();
        } except Exception as _e {
            unit_text = "";
        }
        if unit_text == "PIECE" or unit_text == "LB" or unit_text == "OZ" or unit_text == "CUP" or unit_text == "TBSP" or unit_text == "TSP" or unit_text == "CLOVE" or unit_text == "BUNCH" {
            return unit_text;
        }
        return "PIECE";
    }

    # Unwrap nested OCR payload variants into a consistent shape.
    def has_ocr_content(candidate: any) -> bool {
        if not candidate {
            return false;
        }
        if candidate.text != None {
            return true;
        }
        if candidate.processed_image_b64 != None {
            return true;
        }
        try {
            if candidate.blocks and candidate.blocks.length >= 0 {
                return true;
            }
        } except Exception as _e {
            0;
        }
        return false;
    }

    def unwrap_ocr_payload(ocr_out: dict) -> dict {
        if ocr_out.data and ocr_out.data.result {
            nested = ocr_out.data.result;
            if has_ocr_content(nested) {
                return nested;
            }
        }
        if ocr_out.result {
            nested = ocr_out.result;
            if has_ocr_content(nested) {
                return nested;
            }
        }
        if has_ocr_content(ocr_out) {
            return ocr_out;
        }
        if ocr_out.data and ocr_out.data.result {
            return ocr_out.data.result;
        }
        if ocr_out.result {
            return ocr_out.result;
        }
        return ocr_out;
    }

    # Normalize OCR payload into a plain line-by-line string.
    def normalize_ocr_text(ocr_out: dict) -> str {
        ocr_data = unwrap_ocr_payload(ocr_out);
        raw_text = "";
        try {
            if ocr_data.text != None {
                raw_text = String(ocr_data.text);
            }
        } except Exception as _e {
            raw_text = "";
        }

        if raw_text and raw_text.trim() {
            return raw_text.trim();
        }

        if not ocr_data.blocks or ocr_data.blocks.length == 0 {
            return "";
        }

        parts: list = [];
        for block in ocr_data.blocks {
            try {
                line_text = String(block.text).trim();
                if line_text {
                    parts = parts.concat([line_text]);
                }
            } except Exception as _e {
                # Ignore malformed block rows.
                0;
            }
        }

        if parts.length == 0 {
            return "";
        }
        return parts.join("\n").trim();
    }

    def add_debug(event_type: str, context: str, payload: dict = {}) -> None {
        entry = {
            "time": Date().toString(),
            "type": event_type,
            "context": context,
            "payload": payload
        };
        debug_events = [entry].concat(debug_events);
        if debug_events.length > 50 {
            debug_events = debug_events.slice(0, 50);
        }
        if event_type == "error" {
            last_error = entry;
            console.error("CaloReceipt debug error", entry);
        } else {
            console.log("CaloReceipt debug", entry);
        }
    }

    def build_error_payload(context: str, err: any) -> dict {
        err_text = "";
        err_json = "";
        err_stack = "";

        try {
            err_text = err.toString();
        } except Exception as _e {
            err_text = "Unable to stringify error";
        }
        try {
            err_json = JSON.stringify(err, None, 2);
        } except Exception as _e {
            err_json = "Error object is not JSON-serializable";
        }
        try {
            err_stack = err.stack;
        } except Exception as _e {
            err_stack = "";
        }

        return {
            "context": context,
            "error_text": err_text,
            "error_json": err_json,
            "error_stack": err_stack
        };
    }

    # Build the server-facing profile payload from current form state.
    def build_profile() -> dict {
        return {
            "user_id": parseInt(user_id),
            "age": parseInt(age),
            "sex": sex,
            "height": to_num(height),
            "weight": to_num(weight),
            "dietary_restrictions": split_csv(dietary_restrictions_text),
            "allergies": split_csv(allergies_text),
            "fitness_level": fitness_level,
            "goal": goal
        };
    }

    # Local pantry editor helpers (frontend state only).
    def add_pantry_item() -> None {
        if not ing_name.trim() {
            status = "Ingredient name is required.";
            return;
        }

        pantry = pantry.concat([{
            "name": ing_name.trim(),
            "quantity": to_num(ing_quantity, 1.0),
            "unit": ing_unit,
            "cost": to_num(ing_cost, 0.0),
            "protein": to_num(ing_protein, 0.0),
            "carb": to_num(ing_carb, 0.0),
            "fat": to_num(ing_fat, 0.0)
        }]);

        ing_name = "";
        ing_quantity = "1";
        ing_unit = "PIECE";
        ing_cost = "0";
        ing_protein = "0";
        ing_carb = "0";
        ing_fat = "0";
        status = "Ingredient added to pantry.";
    }

    def remove_pantry_item(name: str) -> None {
        pantry = pantry.filter(
            lambda item: dict -> bool { return item.name != name; }
        );
    }

    # Merge parsed receipt items into pantry by lowercase name + unit.
    def merge_items_into_pantry(items: list) -> None {
        working_pantry: list = pantry;
        for new_item in items {
            new_name = "";
            try {
                new_name = String(new_item.name).trim();
            } except Exception as _e {
                new_name = "";
            }
            if not new_name {
                continue;
            }
            new_unit = normalize_unit_value(new_item.unit);
            merged = false;
            next_pantry: list = [];
            for existing in working_pantry {
                if (
                    String(existing.name).toLowerCase() == new_name.toLowerCase() and
                    normalize_unit_value(existing.unit) == new_unit
                ) {
                    next_pantry = next_pantry.concat([{
                        "name": new_name,
                        "quantity": to_num(existing.quantity.toString()) + to_num(new_item.quantity.toString()),
                        "unit": new_unit,
                        "cost": to_num(existing.cost.toString()) + to_num(new_item.cost.toString()),
                        "protein": to_num(existing.protein.toString()) + to_num(new_item.protein.toString()),
                        "carb": to_num(existing.carb.toString()) + to_num(new_item.carb.toString()),
                        "fat": to_num(existing.fat.toString()) + to_num(new_item.fat.toString())
                    }]);
                    merged = true;
                } else {
                    next_pantry = next_pantry.concat([existing]);
                }
            }
            if not merged {
                next_pantry = next_pantry.concat([{
                    "name": new_name,
                    "quantity": new_item.quantity,
                    "unit": new_unit,
                    "cost": new_item.cost,
                    "protein": new_item.protein,
                    "carb": new_item.carb,
                    "fat": new_item.fat
                }]);
            }
            working_pantry = next_pantry;
        }
        pantry = working_pantry;
    }

    # Prepare editable receipt rows so user can review before pantry insertion.
    def stage_receipt_items_for_review(items: list) -> None {
        staged: list = [];
        row_id = 1;
        for item in items {
            name_text = "";
            qty_text = "1";
            cost_text = "0";
            unit_text = "PIECE";
            try {
                name_text = String(item.name).trim();
            } except Exception as _e {
                name_text = "";
            }
            try {
                qty_raw = String(item.quantity).trim();
                if qty_raw {
                    qty_text = qty_raw;
                }
            } except Exception as _e {
                0;
            }
            try {
                cost_raw = String(item.cost).trim();
                if cost_raw {
                    cost_text = cost_raw;
                }
            } except Exception as _e {
                0;
            }
            unit_text = normalize_unit_value(item.unit);
            if not name_text {
                continue;
            }
            staged = staged.concat([{
                "row_id": row_id,
                "include": true,
                "name": name_text,
                "quantity_text": qty_text,
                "unit": unit_text,
                "cost_text": cost_text
            }]);
            row_id += 1;
        }
        pending_receipt_items = staged;
    }

    def toggle_pending_include(row_id: int, checked: bool) -> None {
        next_items: list = [];
        for item in pending_receipt_items {
            if item.row_id == row_id {
                next_items = next_items.concat([{
                    "row_id": item.row_id,
                    "include": checked,
                    "name": item.name,
                    "quantity_text": item.quantity_text,
                    "unit": item.unit,
                    "cost_text": item.cost_text
                }]);
            } else {
                next_items = next_items.concat([item]);
            }
        }
        pending_receipt_items = next_items;
    }

    def update_pending_name(row_id: int, value: str) -> None {
        next_items: list = [];
        for item in pending_receipt_items {
            if item.row_id == row_id {
                next_items = next_items.concat([{
                    "row_id": item.row_id,
                    "include": item.include,
                    "name": value,
                    "quantity_text": item.quantity_text,
                    "unit": item.unit,
                    "cost_text": item.cost_text
                }]);
            } else {
                next_items = next_items.concat([item]);
            }
        }
        pending_receipt_items = next_items;
    }

    def update_pending_quantity(row_id: int, value: str) -> None {
        next_items: list = [];
        for item in pending_receipt_items {
            if item.row_id == row_id {
                next_items = next_items.concat([{
                    "row_id": item.row_id,
                    "include": item.include,
                    "name": item.name,
                    "quantity_text": value,
                    "unit": item.unit,
                    "cost_text": item.cost_text
                }]);
            } else {
                next_items = next_items.concat([item]);
            }
        }
        pending_receipt_items = next_items;
    }

    def update_pending_unit(row_id: int, value: str) -> None {
        next_items: list = [];
        for item in pending_receipt_items {
            if item.row_id == row_id {
                next_items = next_items.concat([{
                    "row_id": item.row_id,
                    "include": item.include,
                    "name": item.name,
                    "quantity_text": item.quantity_text,
                    "unit": value,
                    "cost_text": item.cost_text
                }]);
            } else {
                next_items = next_items.concat([item]);
            }
        }
        pending_receipt_items = next_items;
    }

    def update_pending_cost(row_id: int, value: str) -> None {
        next_items: list = [];
        for item in pending_receipt_items {
            if item.row_id == row_id {
                next_items = next_items.concat([{
                    "row_id": item.row_id,
                    "include": item.include,
                    "name": item.name,
                    "quantity_text": item.quantity_text,
                    "unit": item.unit,
                    "cost_text": value
                }]);
            } else {
                next_items = next_items.concat([item]);
            }
        }
        pending_receipt_items = next_items;
    }

    def remove_pending_item(row_id: int) -> None {
        pending_receipt_items = pending_receipt_items.filter(
            lambda item: dict -> bool { return item.row_id != row_id; }
        );
    }

    def add_approved_receipt_items_to_pantry() -> None {
        approved: list = [];
        for item in pending_receipt_items {
            if not item.include {
                continue;
            }
            name_clean = item.name.trim();
            if not name_clean {
                continue;
            }
            qty = to_num(item.quantity_text, 1.0);
            cost = to_num(item.cost_text, 0.0);
            if qty <= 0 {
                continue;
            }
            approved = approved.concat([{
                "name": name_clean,
                "quantity": qty,
                "unit": normalize_unit_value(item.unit),
                "cost": cost,
                "protein": 0.0,
                "carb": 0.0,
                "fat": 0.0
            }]);
        }
        if approved.length == 0 {
            status = "No approved receipt items to add.";
            add_debug("error", "ReceiptReview.no_approved_items", {"pending_count": pending_receipt_items.length});
            return;
        }
        merge_items_into_pantry(approved);
        pending_receipt_items = [];
        add_debug("info", "ReceiptReview.added_to_pantry", {"added_count": approved.length, "pantry_count": pantry.length});
        status = "Approved receipt items added to pantry.";
    }

    # Build a higher-contrast processed preview and payload for receipt parsing.
    def build_processed_receipt_image(data_url: str) -> None {
        img = Reflect.construct(Image, []);
        img.onload = lambda _img_ev: any -> None {
            src_w = img.width;
            src_h = img.height;

            max_dim = 1800.0;
            scale = 1.0;
            if src_w > src_h and src_w > max_dim {
                scale = max_dim / src_w;
            } elif src_h >= src_w and src_h > max_dim {
                scale = max_dim / src_h;
            }

            dst_w = Math.max(1, Math.round(src_w * scale));
            dst_h = Math.max(1, Math.round(src_h * scale));

            canvas = document.createElement("canvas");
            canvas.width = dst_w;
            canvas.height = dst_h;
            ctx = canvas.getContext("2d");
            ctx.drawImage(img, 0, 0, dst_w, dst_h);

            img_data = ctx.getImageData(0, 0, dst_w, dst_h);
            px = img_data.data;
            i = 0;
            while i < px.length {
                gray = (0.299 * px[i]) + (0.587 * px[i + 1]) + (0.114 * px[i + 2]);
                boosted = (gray - 128.0) * 1.35 + 128.0;
                if boosted < 0 {
                    boosted = 0;
                } elif boosted > 255 {
                    boosted = 255;
                }
                bw = 0;
                if boosted >= 165 {
                    bw = 255;
                }
                px[i] = bw;
                px[i + 1] = bw;
                px[i + 2] = bw;
                i += 4;
            }
            ctx.putImageData(img_data, 0, 0);

            processed_url = canvas.toDataURL("image/jpeg", 0.95);
            receipt_processed_preview_url = processed_url;
            receipt_processed_b64 = processed_url.split(",")[1];
        };
        img.onerror = lambda _img_err: any -> None {
            receipt_processed_preview_url = receipt_original_preview_url;
            receipt_processed_b64 = receipt_image_b64;
            add_debug("error", "receipt.preprocess_error", {"image_name": receipt_image_name});
        };
        img.src = data_url;
    }

    # Read receipt image as-is (no compression) to preserve line-item fidelity.
    def on_receipt_image_change(e: any) -> None {
        files = e.target.files;
        if not files or files.length == 0 {
            receipt_image_name = "";
            receipt_image_b64 = "";
            receipt_processed_b64 = "";
            receipt_original_preview_url = "";
            receipt_processed_preview_url = "";
            return;
        }
        file = files[0];
        receipt_image_name = file.name;
        if file.type and file.type.trim() {
            receipt_image_mime_type = file.type;
        } else {
            receipt_image_mime_type = "image/jpeg";
        }
        reader = Reflect.construct(FileReader, []);
        reader.onload = lambda ev: any -> None {
            data_url = ev.target.result;
            raw = data_url.split(",")[1];
            receipt_image_b64 = raw;
            receipt_processed_b64 = raw;
            receipt_original_preview_url = data_url;
            receipt_processed_preview_url = data_url;
            build_processed_receipt_image(data_url);
            status = "Receipt image loaded. Preview before/after preprocessing, then click OCR Import.";
        };
        reader.onerror = lambda _ev: any -> None {
            status = "Failed to read selected receipt image.";
            add_debug("error", "receipt.file_read_error", {"file_name": file.name});
        };
        reader.readAsDataURL(file);
    }

    # Run EasyOCR, display OCR text, then parse OCR text with byLLM.
    async def import_receipt_to_pantry -> None {
        if not receipt_image_b64 {
            status = "Select a receipt image first.";
            return;
        }

        loading = true;
        status = "Running OCR on receipt image...";
        try {
            add_debug("request", "ExtractReceiptText", {
                "image_name": receipt_image_name,
                "is_base64": true,
                "image_mime_type": receipt_image_mime_type
            });
            image_payload_b64 = receipt_image_b64;
            if receipt_processed_b64 {
                image_payload_b64 = receipt_processed_b64;
            }
            ocr_result = root spawn ExtractReceiptText(
                image_input=image_payload_b64,
                is_base64=true,
                languages=["en"]
            );
            add_debug("response", "ExtractReceiptText", {"raw_result": ocr_result});
            ocr_out = first_report_payload(ocr_result);
            ocr_data = unwrap_ocr_payload(ocr_out);
            ocr_ok = true;
            if ocr_data.ok == false {
                ocr_ok = false;
            } elif ocr_out.ok == false {
                ocr_ok = false;
            }
            if not ocr_ok {
                if ocr_data.processed_image_b64 {
                    receipt_processed_preview_url = "data:image/jpeg;base64," + ocr_data.processed_image_b64;
                }
                status = "Receipt OCR failed: " + String(ocr_data.error or ocr_out.error or "unknown error");
                add_debug("error", "ExtractReceiptText.reported_error", {"ocr_out": ocr_out, "ocr_data": ocr_data});
                loading = false;
                return;
            }

            ocr_text = normalize_ocr_text(ocr_out);
            receipt_ocr_text = ocr_text;
            if ocr_data.processed_image_b64 {
                receipt_processed_preview_url = "data:image/jpeg;base64," + ocr_data.processed_image_b64;
            }
            add_debug("info", "ExtractReceiptText.normalized", {
                "text_len": ocr_text.length,
                "text_preview": ocr_text.slice(0, 200),
                "has_blocks": (ocr_data.blocks and ocr_data.blocks.length > 0)
            });
            if not ocr_text or not ocr_text.trim() {
                status = "Receipt OCR produced empty text. Try a clearer photo or different crop.";
                add_debug("error", "ExtractReceiptText.empty_text", {"ocr_out": ocr_out, "ocr_data": ocr_data});
                loading = false;
                return;
            }
            status = "Parsing OCR text with LLM...";
            add_debug("request", "ParseReceiptTextToPantry", {
                "receipt_text_len": ocr_text.length,
                "receipt_text_preview": ocr_text.slice(0, 400)
            });
            parse_result = root spawn ParseReceiptTextToPantry(receipt_text=ocr_text);
            add_debug("response", "ParseReceiptTextToPantry", {"raw_result": parse_result});
            parse_raw = first_report_payload(parse_result);
            parse_out = unwrap_parse_payload(parse_raw);
            receipt_parse = parse_out;
            parse_ok = true;
            if parse_out.ok == false {
                parse_ok = false;
            } elif parse_raw.ok == false {
                parse_ok = false;
            }
            if not parse_ok {
                status = "Receipt parse failed: " + String(parse_out.error or parse_raw.error or "unknown error");
                add_debug("error", "ParseReceiptTextToPantry.reported_error", {"parse_raw": parse_raw, "parse_out": parse_out});
                loading = false;
                return;
            }

            parsed_items: list = [];
            try {
                if parse_out.items and parse_out.items.length >= 0 {
                    parsed_items = parse_out.items;
                }
            } except Exception as _e {
                parsed_items = [];
            }
            add_debug("info", "ParseReceiptTextToPantry.items_extracted", {"item_count": parsed_items.length});
            stage_receipt_items_for_review(parsed_items);
            status = "OCR complete. Review parsed items and click Add Approved Items.";
        } except Exception as e {
            err_payload = build_error_payload("ReceiptImport.exception", e);
            add_debug("error", "ReceiptImport.exception", err_payload);
            status = "Receipt import failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # After recipe generation, subtract used quantities from local pantry inventory.
    def subtract_recipe_from_pantry(recipe_ingredients: list) -> None {
        updated_pantry: list = [];
        for pantry_item in pantry {
            used_qty: float = 0.0;
            for recipe_item in recipe_ingredients {
                if recipe_item.name.toLowerCase() == pantry_item.name.toLowerCase() {
                    used_qty += recipe_item.quantity;
                }
            }
            remaining_qty = pantry_item.quantity - used_qty;
            if remaining_qty > 0 {
                updated_pantry = updated_pantry.concat([{
                    "name": pantry_item.name,
                    "quantity": remaining_qty,
                    "unit": pantry_item.unit,
                    "cost": pantry_item.cost,
                    "protein": pantry_item.protein,
                    "carb": pantry_item.carb,
                    "fat": pantry_item.fat
                }]);
            }
        }
        pantry = updated_pantry;
    }

    # Persist profile to graph storage.
    async def save_user_profile -> None {
        if not is_int_str(user_id) {
            status = "Save failed: user_id must be an integer.";
            add_debug("error", "save_user_profile.validation", {"user_id": user_id, "reason": "not integer"});
            return;
        }
        if not is_int_str(age) {
            status = "Save failed: age must be an integer.";
            add_debug("error", "save_user_profile.validation", {"age": age, "reason": "not integer"});
            return;
        }
        if not is_num_str(height) {
            status = "Save failed: height must be a number (inches).";
            add_debug("error", "save_user_profile.validation", {"height": height, "reason": "not number"});
            return;
        }
        if not is_num_str(weight) {
            status = "Save failed: weight must be a number (pounds).";
            add_debug("error", "save_user_profile.validation", {"weight": weight, "reason": "not number"});
            return;
        }

        loading = true;
        status = "Saving user profile...";
        try {
            profile_payload = build_profile();
            add_debug("request", "SaveUserProfile", {"profile": profile_payload});
            result = root spawn SaveUserProfile(profile=profile_payload);
            add_debug("response", "SaveUserProfile", {"raw_result": result});

            save_out = result.reports[0];
            if save_out.saved {
                user_profile = profile_payload;
                status = "User profile saved.";
            } else {
                status = "Save failed: " + JSON.stringify(save_out, None, 2);
                add_debug("error", "SaveUserProfile.reported_error", {"save_out": save_out});
            }
        } except Exception as e {
            err_payload = build_error_payload("SaveUserProfile.exception", e);
            add_debug("error", "SaveUserProfile.exception", err_payload);
            status = "Save failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Load current profile from backend into form + UI state.
    async def load_user_profile -> None {
        loading = true;
        status = "Loading user profile...";
        try {
            add_debug("request", "GetUserProfile", {});
            result = root spawn GetUserProfile();
            add_debug("response", "GetUserProfile", {"raw_result": result});
            data = result.reports[0];
            if Object.keys(data).length > 0 {
                user_profile = data;
                user_id = data.user_id.toString();
                age = data.age.toString();
                sex = data.sex.toUpperCase();
                height = data.height.toString();
                weight = data.weight.toString();
                dietary_restrictions_text = data.dietary_restrictions.join(", ");
                allergies_text = data.allergies.join(", ");
                fitness_level = data.fitness_level.toUpperCase();
                goal = data.goal.toUpperCase();
                status = "User profile loaded.";
            } else {
                status = "No saved user profile found.";
            }
        } except Exception as e {
            err_payload = build_error_payload("GetUserProfile.exception", e);
            add_debug("error", "GetUserProfile.exception", err_payload);
            status = "Load failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Delete stored profile.
    async def clear_user_profile -> None {
        loading = true;
        status = "Clearing user profile...";
        try {
            add_debug("request", "ClearUserProfile", {});
            root spawn ClearUserProfile();
            add_debug("response", "ClearUserProfile", {"ok": true});
            user_profile = {};
            macro_needs = {};
            status = "User profile cleared.";
        } except Exception as e {
            err_payload = build_error_payload("ClearUserProfile.exception", e);
            add_debug("error", "ClearUserProfile.exception", err_payload);
            status = "Clear failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Trigger macro calculation from stored profile.
    async def generate_macro_needs -> None {
        loading = true;
        status = "Generating macro needs...";
        try {
            add_debug("request", "GenerateUserMacroNeeds", {});
            result = root spawn GenerateUserMacroNeeds();
            add_debug("response", "GenerateUserMacroNeeds", {"raw_result": result});
            macro_out = result.reports[0];
            if macro_out.ok {
                macro_needs = macro_out;
                status = "Macro needs generated.";
            } else {
                macro_needs = {};
                status = "Macro generation failed: " + macro_out.error;
                add_debug("error", "GenerateUserMacroNeeds.reported_error", {"macro_out": macro_out});
            }
        } except Exception as e {
            err_payload = build_error_payload("GenerateUserMacroNeeds.exception", e);
            add_debug("error", "GenerateUserMacroNeeds.exception", err_payload);
            status = "Macro generation failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Generate recipe from profile + pantry, then update local pantry quantities.
    async def generate_recipe -> None {
        if pantry.length == 0 {
            status = "Add pantry ingredients first.";
            return;
        }

        if Object.keys(user_profile).length == 0 {
            if not is_int_str(user_id) {
                status = "Recipe generation failed: user_id must be an integer.";
                add_debug("error", "GenerateRecipeFromPantry.validation", {"user_id": user_id, "reason": "not integer"});
                return;
            }
            if not is_int_str(age) {
                status = "Recipe generation failed: age must be an integer.";
                add_debug("error", "GenerateRecipeFromPantry.validation", {"age": age, "reason": "not integer"});
                return;
            }
            if not is_num_str(height) {
                status = "Recipe generation failed: height must be numeric.";
                add_debug("error", "GenerateRecipeFromPantry.validation", {"height": height, "reason": "not number"});
                return;
            }
            if not is_num_str(weight) {
                status = "Recipe generation failed: weight must be numeric.";
                add_debug("error", "GenerateRecipeFromPantry.validation", {"weight": weight, "reason": "not number"});
                return;
            }
        }

        profile_obj = build_profile();
        if Object.keys(user_profile).length > 0 {
            profile_obj = {
                "user_id": user_profile.user_id,
                "age": user_profile.age,
                "sex": user_profile.sex.toUpperCase(),
                "height": user_profile.height,
                "weight": user_profile.weight,
                "dietary_restrictions": user_profile.dietary_restrictions,
                "allergies": user_profile.allergies,
                "fitness_level": user_profile.fitness_level.toUpperCase(),
                "goal": user_profile.goal.toUpperCase()
            };
        }
        if profile_obj.user_id == None or profile_obj.age == None or profile_obj.height == None or profile_obj.weight == None {
            status = "Recipe generation failed: profile has missing numeric fields. Save or reload your profile first.";
            add_debug("error", "GenerateRecipeFromPantry.validation", {"profile": profile_obj, "reason": "missing numeric fields"});
            return;
        }
        loading = true;
        status = "Generating recipe from pantry...";
        try {
            add_debug("request", "GenerateRecipeFromPantry", {"profile": profile_obj, "pantry_ingredients": pantry});
            result = root spawn GenerateRecipeFromPantry(
                profile=profile_obj,
                pantry_ingredients=pantry
            );
            add_debug("response", "GenerateRecipeFromPantry", {"raw_result": result});
            generated = first_report_payload(result);
            if generated.ok == false {
                status = "Recipe generation failed: " + String(generated.error or "unknown error");
                add_debug("error", "GenerateRecipeFromPantry.reported_error", {"generated": generated});
                loading = false;
                return;
            }
            recipe = generated;
            if generated.ingredients {
                subtract_recipe_from_pantry(generated.ingredients);
            }
            status = "Recipe generated and pantry updated.";
        } except Exception as e {
            err_payload = build_error_payload("GenerateRecipeFromPantry.exception", e);
            add_debug("error", "GenerateRecipeFromPantry.exception", err_payload);
            status = "Recipe generation failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Read latest stored generated recipe.
    async def reload_saved_recipe -> None {
        loading = true;
        status = "Loading saved recipe...";
        try {
            add_debug("request", "ListGeneratedRecipe", {});
            result = root spawn ListGeneratedRecipe();
            add_debug("response", "ListGeneratedRecipe", {"raw_result": result});
            recipe = result.reports[0];
            status = "Saved recipe loaded.";
        } except Exception as e {
            err_payload = build_error_payload("ListGeneratedRecipe.exception", e);
            add_debug("error", "ListGeneratedRecipe.exception", err_payload);
            status = "Load recipe failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Remove stored generated recipe state.
    async def clear_recipe -> None {
        loading = true;
        status = "Clearing generated recipe...";
        try {
            add_debug("request", "ClearGeneratedRecipe", {});
            root spawn ClearGeneratedRecipe();
            add_debug("response", "ClearGeneratedRecipe", {"ok": true});
            recipe = {};
            status = "Generated recipe cleared.";
        } except Exception as e {
            err_payload = build_error_payload("ClearGeneratedRecipe.exception", e);
            add_debug("error", "ClearGeneratedRecipe.exception", err_payload);
            status = "Clear recipe failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # UI sections:
    # - Status + debug
    # - User profile + macro output
    # - Pantry editor
    # - Recipe output
    return
        <div
            style={{
                "fontFamily": "'Avenir Next', 'Segoe UI', sans-serif",
                "background": "linear-gradient(140deg, #f6f8fc 0%, #e8fff7 55%, #fff3de 100%)",
                "minHeight": "100vh",
                "padding": "20px",
                "color": "#11203a"
            }}
        >
            <div
                style={{
                    "maxWidth": "1100px",
                    "margin": "0 auto",
                    "display": "grid",
                    "gap": "16px"
                }}
            >
                <h1 style={{"margin": "0", "fontSize": "2rem"}}>
                    CaloReceipt Test Console
                </h1>
                <div
                    style={{
                        "padding": "10px 12px",
                        "borderRadius": "10px",
                        "background": "#ffffffcc",
                        "border": "1px solid #d9e2ef",
                        "fontWeight": "600"
                    }}
                >
                    {("Working..." if loading else "Ready")} | {status}
                </div>
                <div
                    style={{
                        "background": "#fff7ed",
                        "border": "1px solid #fdba74",
                        "borderRadius": "14px",
                        "padding": "16px"
                    }}
                >
                    <div style={{"display": "flex", "gap": "8px", "alignItems": "center", "flexWrap": "wrap"}}>
                        <h2 style={{"margin": "0"}}>Debug Console</h2>
                        <button onClick={lambda -> None { show_debug = not show_debug; }}>
                            {( "Hide Debug" if show_debug else "Show Debug" )}
                        </button>
                        <button onClick={lambda -> None { debug_events = []; last_error = {}; }}>
                            Clear Debug Logs
                        </button>
                    </div>
                    {(
                        <div style={{"marginTop": "10px"}}>
                            <h3>Last Error</h3>
                            <pre style={{"background": "#111827", "color": "#fecaca", "padding": "10px", "borderRadius": "8px", "overflowX": "auto"}}>
                                {JSON.stringify(last_error, None, 2)}
                            </pre>
                            <h3>Debug Events (latest 50)</h3>
                            <pre style={{"background": "#111827", "color": "#bfdbfe", "padding": "10px", "borderRadius": "8px", "overflowX": "auto"}}>
                                {JSON.stringify(debug_events, None, 2)}
                            </pre>
                        </div>
                    ) if show_debug else <div /> }
                </div>
                <div
                    style={{
                        "background": "#ffffffd9",
                        "border": "1px solid #d9e2ef",
                        "borderRadius": "14px",
                        "padding": "16px"
                    }}
                >
                    <h2>User Profile</h2>
                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(4, minmax(0, 1fr))", "gap": "8px"}}>
                        <input value={user_id} onChange={lambda e: any -> None { user_id = e.target.value; }} placeholder="User ID" />
                        <input value={age} onChange={lambda e: any -> None { age = e.target.value; }} placeholder="Age" />
                        <input value={height} onChange={lambda e: any -> None { height = e.target.value; }} placeholder="Height (in)" />
                        <input value={weight} onChange={lambda e: any -> None { weight = e.target.value; }} placeholder="Weight (lb)" />
                        <select value={sex} onChange={lambda e: any -> None { sex = e.target.value; }}>
                            <option value="MALE">MALE</option>
                            <option value="FEMALE">FEMALE</option>
                            <option value="OTHER">OTHER</option>
                            <option value="PREFER_NOT_TO_SAY">PREFER_NOT_TO_SAY</option>
                        </select>
                        <select value={fitness_level} onChange={lambda e: any -> None { fitness_level = e.target.value; }}>
                            <option value="SEDENTARY">SEDENTARY</option>
                            <option value="LIGHTLY_ACTIVE">LIGHTLY_ACTIVE</option>
                            <option value="MODERATELY_ACTIVE">MODERATELY_ACTIVE</option>
                            <option value="VERY_ACTIVE">VERY_ACTIVE</option>
                            <option value="ATHLETE">ATHLETE</option>
                        </select>
                        <select value={goal} onChange={lambda e: any -> None { goal = e.target.value; }}>
                            <option value="FAT_LOSS">FAT_LOSS</option>
                            <option value="MAINTENANCE">MAINTENANCE</option>
                            <option value="LEAN_BULK">LEAN_BULK</option>
                            <option value="MUSCLE_GAIN">MUSCLE_GAIN</option>
                            <option value="ENDURANCE_PERFORMANCE">ENDURANCE_PERFORMANCE</option>
                        </select>
                        <input value={dietary_restrictions_text} onChange={lambda e: any -> None { dietary_restrictions_text = e.target.value; }} placeholder="dietary restrictions (comma separated)" />
                        <input value={allergies_text} onChange={lambda e: any -> None { allergies_text = e.target.value; }} placeholder="allergies (comma separated)" />
                    </div>
                    <div style={{"display": "flex", "gap": "8px", "marginTop": "12px", "flexWrap": "wrap"}}>
                        <button onClick={save_user_profile}>Save User</button>
                        <button onClick={load_user_profile}>Load User</button>
                        <button onClick={clear_user_profile}>Clear User</button>
                        <button onClick={generate_macro_needs}>Generate Macros</button>
                    </div>
                    <h3>Saved User</h3>
                    <pre style={{"background": "#0f172a", "color": "#d1fae5", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto"}}>
                        {JSON.stringify(user_profile, None, 2)}
                    </pre>
                    <h3>Macro Needs</h3>
                    <pre style={{"background": "#0f172a", "color": "#d1fae5", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto"}}>
                        {JSON.stringify(macro_needs, None, 2)}
                    </pre>
                </div>
                <div
                    style={{
                        "background": "#ffffffd9",
                        "border": "1px solid #d9e2ef",
                        "borderRadius": "14px",
                        "padding": "16px"
                    }}
                >
                    <h2>Receipt OCR Import</h2>
                    <div style={{"display": "flex", "gap": "10px", "alignItems": "center", "flexWrap": "wrap"}}>
                        <input type="file" accept="image/*" onChange={on_receipt_image_change} />
                        <button onClick={import_receipt_to_pantry}>OCR Import To Pantry</button>
                        <span>{receipt_image_name}</span>
                    </div>
                    <div style={{"display": "grid", "gridTemplateColumns": "1fr 1fr", "gap": "10px", "marginTop": "10px"}}>
                        <div>
                            <h3 style={{"marginTop": "0"}}>Before Preprocessing</h3>
                            {(
                                <img
                                    src={receipt_original_preview_url}
                                    alt="Receipt original preview"
                                    style={{"width": "100%", "maxHeight": "320px", "objectFit": "contain", "background": "#ffffff", "border": "1px solid #d9e2ef", "borderRadius": "8px"}}
                                />
                            ) if receipt_original_preview_url else <div>No image selected.</div> }
                        </div>
                        <div>
                            <h3 style={{"marginTop": "0"}}>After Preprocessing</h3>
                            {(
                                <img
                                    src={receipt_processed_preview_url}
                                    alt="Receipt processed preview"
                                    style={{"width": "100%", "maxHeight": "320px", "objectFit": "contain", "background": "#ffffff", "border": "1px solid #d9e2ef", "borderRadius": "8px"}}
                                />
                            ) if receipt_processed_preview_url else <div>No processed preview yet.</div> }
                        </div>
                    </div>
                    <h3>OCR Text</h3>
                    <pre style={{"background": "#0f172a", "color": "#bfdbfe", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto", "maxHeight": "180px", "overflowY": "auto"}}>
                        {receipt_ocr_text}
                    </pre>
                    <h3>Parsed Receipt Items</h3>
                    <pre style={{"background": "#0f172a", "color": "#fde68a", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto"}}>
                        {JSON.stringify(receipt_parse, None, 2)}
                    </pre>
                    <h3>Review Parsed Items Before Add</h3>
                    <div style={{"display": "flex", "gap": "8px", "marginBottom": "8px", "flexWrap": "wrap"}}>
                        <button onClick={add_approved_receipt_items_to_pantry}>Add Approved Items</button>
                        <button onClick={lambda -> None { pending_receipt_items = []; }}>Discard Review Items</button>
                    </div>
                    {(
                        <div>No pending receipt items.</div>
                    )
                    if pending_receipt_items.length == 0
                    else (
                        <table style={{"width": "100%", "borderCollapse": "collapse"}}>
                            <thead>
                                <tr>
                                    <th>Add</th><th>Name</th><th>Qty</th><th>Unit</th><th>Cost</th><th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {pending_receipt_items.map(
                                    lambda item: dict -> JsxElement { return
                                        <tr key={item.row_id.toString()}>
                                            <td>
                                                <input
                                                    type="checkbox"
                                                    checked={item.include}
                                                    onChange={lambda e: any -> None { toggle_pending_include(item.row_id, e.target.checked); }}
                                                />
                                            </td>
                                            <td>
                                                <input
                                                    value={item.name}
                                                    onChange={lambda e: any -> None { update_pending_name(item.row_id, e.target.value); }}
                                                />
                                            </td>
                                            <td>
                                                <input
                                                    value={item.quantity_text}
                                                    onChange={lambda e: any -> None { update_pending_quantity(item.row_id, e.target.value); }}
                                                />
                                            </td>
                                            <td>
                                                <select
                                                    value={item.unit}
                                                    onChange={lambda e: any -> None { update_pending_unit(item.row_id, e.target.value); }}
                                                >
                                                    <option value="PIECE">PIECE</option>
                                                    <option value="LB">LB</option>
                                                    <option value="OZ">OZ</option>
                                                    <option value="CUP">CUP</option>
                                                    <option value="TBSP">TBSP</option>
                                                    <option value="TSP">TSP</option>
                                                    <option value="CLOVE">CLOVE</option>
                                                    <option value="BUNCH">BUNCH</option>
                                                </select>
                                            </td>
                                            <td>
                                                <input
                                                    value={item.cost_text}
                                                    onChange={lambda e: any -> None { update_pending_cost(item.row_id, e.target.value); }}
                                                />
                                            </td>
                                            <td>
                                                <button onClick={lambda -> None { remove_pending_item(item.row_id); }}>Remove</button>
                                            </td>
                                        </tr>; }
                                )}
                            </tbody>
                        </table>
                    )}
                </div>
                <div
                    style={{
                        "background": "#ffffffd9",
                        "border": "1px solid #d9e2ef",
                        "borderRadius": "14px",
                        "padding": "16px"
                    }}
                >
                    <h2>Pantry</h2>
                    <div style={{"display": "grid", "gridTemplateColumns": "2fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr", "gap": "8px"}}>
                        <input value={ing_name} onChange={lambda e: any -> None { ing_name = e.target.value; }} placeholder="name" />
                        <input value={ing_quantity} onChange={lambda e: any -> None { ing_quantity = e.target.value; }} placeholder="qty" />
                        <select value={ing_unit} onChange={lambda e: any -> None { ing_unit = e.target.value; }}>
                            <option value="PIECE">PIECE</option>
                            <option value="LB">LB</option>
                            <option value="OZ">OZ</option>
                            <option value="CUP">CUP</option>
                            <option value="TBSP">TBSP</option>
                            <option value="TSP">TSP</option>
                            <option value="CLOVE">CLOVE</option>
                            <option value="BUNCH">BUNCH</option>
                        </select>
                        <input value={ing_cost} onChange={lambda e: any -> None { ing_cost = e.target.value; }} placeholder="cost" />
                        <input value={ing_protein} onChange={lambda e: any -> None { ing_protein = e.target.value; }} placeholder="protein" />
                        <input value={ing_carb} onChange={lambda e: any -> None { ing_carb = e.target.value; }} placeholder="carb" />
                        <input value={ing_fat} onChange={lambda e: any -> None { ing_fat = e.target.value; }} placeholder="fat" />
                        <button onClick={add_pantry_item}>Add</button>
                    </div>
                    <div style={{"marginTop": "12px"}}>
                        {(
                            <div>No pantry items yet.</div>
                        )
                        if pantry.length == 0
                        else (
                            <table style={{"width": "100%", "borderCollapse": "collapse"}}>
                                <thead>
                                    <tr>
                                        <th>Name</th><th>Qty</th><th>Unit</th><th>Cost</th><th>P</th><th>C</th><th>F</th><th>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {pantry.map(
                                        lambda item: dict, idx: int -> JsxElement { return
                                            <tr key={item.name + ":" + item.unit + ":" + idx.toString()}>
                                                <td>{item.name}</td>
                                                <td>{item.quantity}</td>
                                                <td>{item.unit}</td>
                                                <td>{item.cost}</td>
                                                <td>{item.protein}</td>
                                                <td>{item.carb}</td>
                                                <td>{item.fat}</td>
                                                <td><button onClick={lambda -> None { remove_pantry_item(item.name); }}>Remove</button></td>
                                            </tr>; }
                                    )}
                                </tbody>
                            </table>
                        )}
                    </div>
                </div>
                <div
                    style={{
                        "background": "#ffffffd9",
                        "border": "1px solid #d9e2ef",
                        "borderRadius": "14px",
                        "padding": "16px"
                    }}
                >
                    <h2>Recipe</h2>
                    <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                        <button onClick={generate_recipe}>Generate Recipe From Pantry</button>
                        <button onClick={reload_saved_recipe}>Load Saved Recipe</button>
                        <button onClick={clear_recipe}>Clear Recipe</button>
                    </div>
                    <pre style={{"background": "#0f172a", "color": "#fef3c7", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto"}}>
                        {JSON.stringify(recipe, None, 2)}
                    </pre>
                    {(
                        <ol>
                            {recipe.instructions.map(
                                lambda step: str -> JsxElement { return <li key={step}>{step}</li>; }
                            )}
                        </ol>
                    )
                    if (recipe and recipe.instructions and recipe.instructions.length > 0)
                    else <div /> }
                </div>
            </div>
        </div>;
}
