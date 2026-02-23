"""Receipt OCR module.
Uses PaddleOCR in document mode plus receipt-specific preprocessing.
"""

import os;
import base64;
import importlib;

glob _ocr_engine_cache: dict = {};

# Load image from base64 payload or file path.
def _load_image(image_input: str, is_base64: bool, np: object, cv2: object) -> object {
    if is_base64 {
        raw_bytes = base64.b64decode(image_input);
        np_buf = np.frombuffer(raw_bytes, dtype=np.uint8);
        image = cv2.imdecode(np_buf, cv2.IMREAD_COLOR);
        return image;
    }
    if not os.path.exists(image_input) {
        return None;
    }
    return cv2.imread(image_input, cv2.IMREAD_COLOR);
}

# Crop to dominant receipt contour to remove surrounding background.
def _crop_receipt_edges(image: object, cv2: object, np: object) -> object {
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);
    blur = cv2.GaussianBlur(gray, (5, 5), 0);
    edge_img = cv2.Canny(blur, 50, 150);

    contours_data = cv2.findContours(edge_img, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE);
    contours = contours_data[0];
    if len(contours_data) > 2 {
        contours = contours_data[1];
    }

    if len(contours) == 0 {
        return image;
    }

    h = int(image.shape[0]);
    w = int(image.shape[1]);
    image_area = float(h) * float(w);

    max_area = 0.0;
    best = None;
    for c in contours {
        area = cv2.contourArea(c);
        if area > max_area {
            max_area = area;
            best = c;
        }
    }

    if best is None {
        return image;
    }

    if max_area < (0.08 * image_area) {
        return image;
    }

    rect = cv2.boundingRect(best);
    x = int(rect[0]);
    y = int(rect[1]);
    bw = int(rect[2]);
    bh = int(rect[3]);
    pad = 8;
    x0 = max(0, x - pad);
    y0 = max(0, y - pad);
    x1 = min(w, x + bw + pad);
    y1 = min(h, y + bh + pad);
    return image[y0:y1, x0:x1];
}

# Normalize receipt size to keep OCR fast and stable.
def _resize_for_ocr(gray: object, cv2: object) -> object {
    h = int(gray.shape[0]);
    w = int(gray.shape[1]);
    if h <= 0 or w <= 0 {
        return gray;
    }

    min_w = 900.0;
    max_w = 1400.0;
    target_w = float(w);

    if float(w) < min_w {
        target_w = min_w;
    } elif float(w) > max_w {
        target_w = max_w;
    }

    if target_w == float(w) {
        return gray;
    }

    scale = target_w / float(w);
    new_w = int(float(w) * scale);
    new_h = int(float(h) * scale);
    return cv2.resize(gray, (new_w, new_h), interpolation=cv2.INTER_CUBIC);
}

# Deskew text block using minAreaRect angle from foreground pixels.
def _deskew(gray: object, cv2: object, np: object) -> object {
    thresh = cv2.threshold(gray, 0, 255, 8)[1];
    inv = 255 - thresh;
    coords = np.column_stack(np.where(inv > 0));
    if len(coords) < 100 {
        return gray;
    }

    angle = cv2.minAreaRect(coords)[-1];
    if angle < -45 {
        angle = 90 + angle;
    }

    if angle > 45 {
        angle = angle - 90;
    }

    h = gray.shape[0];
    w = gray.shape[1];
    center = (w // 2, h // 2);
    mat = cv2.getRotationMatrix2D(center, angle, 1.0);
    return cv2.warpAffine(gray, mat, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE);
}

# Receipt-focused preprocessing pipeline:
# 1) edge crop 2) grayscale 3) denoise 4) CLAHE contrast 5) deskew 6) adaptive threshold.
def _preprocess_receipt(image: object, cv2: object, np: object) -> object {
    cropped = _crop_receipt_edges(image, cv2, np);
    gray = cv2.cvtColor(cropped, cv2.COLOR_BGR2GRAY);
    gray = _resize_for_ocr(gray, cv2);

    # Fast denoise pass; much cheaper than NLMeans and good enough for receipts.
    denoised = cv2.GaussianBlur(gray, (3, 3), 0);
    clahe = cv2.createCLAHE(clipLimit=1.8, tileGridSize=(8, 8));
    contrast = clahe.apply(denoised);

    bin_img = cv2.adaptiveThreshold(
        contrast,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        25,
        9
    );

    # Paddle OCR is more stable with 3-channel input arrays.
    return cv2.cvtColor(bin_img, cv2.COLOR_GRAY2BGR);
}

# Build/load a cached PaddleOCR engine.
def _get_paddle_engine(languages: list[str]) -> object {
    lang = "en";
    if languages != [] {
        lang = str(languages[0]).lower();
    }

    paddleocr_mod = importlib.import_module("paddleocr");
    PaddleOCR = paddleocr_mod.PaddleOCR;

    # Prefer GPU OCR when available; fallback to CPU if GPU init fails.
    prefer_gpu = True;
    cache_key = "{}|{}".format(lang, ("gpu" if prefer_gpu else "cpu"));
    if cache_key in _ocr_engine_cache {
        return _ocr_engine_cache[cache_key];
    }

    engine = None;
    try {
        # Speed mode: disable heavier document features.
        engine = PaddleOCR(
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            use_textline_orientation=False,
            lang=lang,
            device="gpu:0"
        );
    } except Exception as _e {
        try {
            # PaddleOCR 2.x fallback with GPU.
            engine = PaddleOCR(
                use_angle_cls=True,
                lang=lang,
                use_gpu=True
            );
        } except Exception as _e2 {
            try {
                # PaddleOCR 3.x CPU fallback.
                engine = PaddleOCR(
                    use_doc_orientation_classify=False,
                    use_doc_unwarping=False,
                    use_textline_orientation=False,
                    lang=lang,
                    device="cpu"
                );
            } except Exception as _e3 {
                # PaddleOCR 2.x CPU fallback.
                engine = PaddleOCR(
                    use_angle_cls=True,
                    lang=lang,
                    use_gpu=False
                );
            }
        }
    }

    _ocr_engine_cache[cache_key] = engine;
    return engine;
}

# Normalize OCR result formats and sort lines as a single-column document.
def _extract_lines(result: object) -> list {
    lines: list = [];

    # Normalize top-level container.
    if not isinstance(result, list) and not isinstance(result, tuple) {
        return lines;
    }
    if result == [] {
        return lines;
    }

    # PaddleOCR 3.x predict() style.
    if isinstance(result[0], dict) and ("rec_texts" in result[0]) {
        first = result[0];
        texts = first.get("rec_texts", []);
        scores = first.get("rec_scores", []);
        i = 0;
        for text in texts {
            conf = 0.0;
            if i < len(scores) {
                conf = float(scores[i]);
            }
            lines.append({"text": str(text).strip(), "conf": conf, "y": float(i), "x": 0.0});
            i += 1;
        }
        return lines;
    }

    # PaddleOCR 2.x ocr() style.
    for page in result {
        if not isinstance(page, list) and not isinstance(page, tuple) {
            continue;
        }
        for row in page {
            if not isinstance(row, list) and not isinstance(row, tuple) {
                continue;
            }
            pair = None;
            try {
                pair = row[1];
            } except Exception as _e {
                continue;
            }
            if not isinstance(pair, list) and not isinstance(pair, tuple) {
                continue;
            }

            text = "";
            conf = 0.0;
            try {
                text = str(pair[0]).strip();
                conf = float(pair[1]);
            } except Exception as _e {
                continue;
            }
            if text == "" {
                continue;
            }
            lines.append({"text": text, "conf": conf, "y": 0.0, "x": 0.0});
        }
    }

    # Single-column ordering hint: top-to-bottom then left-to-right.
    lines.sort(key=lambda r: dict -> float : r["x"]);
    lines.sort(key=lambda r: dict -> float : r["y"]);
    return lines;
}

# Public OCR function used by frontend: returns plain text + block metadata.
def:pub extract_receipt_text(image_input: str, is_base64: bool, languages: list[str]) -> dict {
    try {
        sys = importlib.import_module("sys");

        missing_text = "";
        missing_count = 0;

        try {
            np = importlib.import_module("numpy");
        } except Exception as _e {
            missing_text = "numpy";
            missing_count += 1;
        }

        try {
            cv2 = importlib.import_module("cv2");
        } except Exception as _e {
            if missing_text == "" {
                missing_text = "opencv-python-headless";
            } else {
                missing_text = "{}, {}".format(missing_text, "opencv-python-headless");
            }
            missing_count += 1;
        }

        try {
            importlib.import_module("paddleocr");
        } except Exception as _e {
            if missing_text == "" {
                missing_text = "paddleocr";
            } else {
                missing_text = "{}, {}".format(missing_text, "paddleocr");
            }
            missing_count += 1;
        }

        if missing_count > 0 {
            return {
                "ok": False,
                "text": "",
                "variant_index": -1,
                "score": -1.0,
                "block_count": 0,
                "blocks": [],
                "error": "Missing OCR dependencies: {}. Python exe: {}. Install with: pip install numpy opencv-python-headless paddleocr paddlepaddle".format(missing_text, sys.executable)
            };
        }

        image = _load_image(image_input, is_base64, np, cv2);
        if image is None {
            return {
                "ok": False,
                "text": "",
                "variant_index": -1,
                "score": -1.0,
                "block_count": 0,
                "blocks": [],
                "error": "Failed to decode receipt image"
            };
        }

        processed = _preprocess_receipt(image, cv2, np);
        engine = _get_paddle_engine(languages);

        processed_b64 = "";
        try {
            enc_out = cv2.imencode(".jpg", processed);
            ok_enc = enc_out[0];
            enc_buf = enc_out[1];
            if ok_enc {
                processed_b64 = base64.b64encode(enc_buf.tobytes()).decode("utf-8");
            }
        } except Exception as _e {
            processed_b64 = "";
        }

        raw_result = None;
        try {
            raw_result = engine.ocr(processed, cls=False);
        } except Exception as _e {
            try {
                # Fallback for versions where cls is not a supported arg.
                raw_result = engine.ocr(processed);
            } except Exception as _e2 {
                return {
                    "ok": False,
                    "text": "",
                    "variant_index": -1,
                    "score": -1.0,
                    "block_count": 0,
                    "blocks": [],
                    "error": "PaddleOCR inference failed: {}".format(str(_e2))
                };
            }
        }

        lines = _extract_lines(raw_result);
        if lines == [] {
            return {
                "ok": False,
                "text": "",
                "variant_index": -1,
                "score": -1.0,
                "block_count": 0,
                "blocks": [],
                "processed_image_b64": processed_b64,
                "processed_image_mime_type": "image/jpeg",
                "error": "No text detected in image."
            };
        }

        text_accum = "";
        conf_sum = 0.0;
        count = 0.0;
        blocks: list = [];
        for row in lines {
            t = str(row["text"]).strip();
            if t == "" {
                continue;
            }
            if text_accum == "" {
                text_accum = t;
            } else {
                text_accum = "{}\n{}".format(text_accum, t);
            }
            conf = float(row["conf"]);
            conf_sum += conf;
            count += 1.0;
            blocks.append({"text": t, "conf": conf, "y": row["y"], "x": row["x"]});
        }

        avg_conf = 0.0;
        if count > 0 {
            avg_conf = conf_sum / count;
        }

        return {
            "ok": True,
            "text": text_accum,
            "variant_index": 0,
            "score": avg_conf,
            "block_count": int(count),
            "blocks": blocks,
            "processed_image_b64": processed_b64,
            "processed_image_mime_type": "image/jpeg",
            "error": ""
        };
    } except Exception as e {
        return {
            "ok": False,
            "text": "",
            "variant_index": -1,
            "score": -1.0,
            "block_count": 0,
            "blocks": [],
            "error": str(e)
        };
    }
}

walker:pub ExtractReceiptText {
    has image_input: str;
    has is_base64: bool = False;
    has languages: list[str] = [];

    can run with Root entry {
        report extract_receipt_text(self.image_input, self.is_base64, self.languages);
    }
}
