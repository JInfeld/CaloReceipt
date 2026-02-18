"""Receipt OCR module.
Provides image preprocessing + EasyOCR extraction for receipt photos.
"""

import os;
import base64;
import importlib;

glob _ocr_reader_cache: dict = {};

# Single public OCR function used by the walker and frontend.
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
            importlib.import_module("easyocr");
        } except Exception as _e {
            if missing_text == "" {
                missing_text = "easyocr";
            } else {
                missing_text = "{}, {}".format(missing_text, "easyocr");
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
                "error": "Missing OCR dependencies: {}. Python exe: {}. Install with: pip install numpy opencv-python-headless easyocr".format(missing_text, sys.executable)
            };
        }

        langs: list[str] = languages;
        if langs == [] {
            langs = ["en"];
        }

        lang_key = "";
        for lang in langs {
            if lang_key == "" {
                lang_key = str(lang);
            } else {
                lang_key = "{}|{}".format(lang_key, str(lang));
            }
        }
        if lang_key in _ocr_reader_cache {
            reader = _ocr_reader_cache[lang_key];
        } else {
            easyocr = importlib.import_module("easyocr");
            # Help SSL verification on macOS/conda by pointing to certifi's CA bundle.
            try {
                certifi = importlib.import_module("certifi");
                ca_file = certifi.where();
                os.environ["SSL_CERT_FILE"] = ca_file;
                os.environ["REQUESTS_CA_BUNDLE"] = ca_file;
                os.environ["CURL_CA_BUNDLE"] = ca_file;
            } except Exception as _e {
                _unused = 0;
            }
            try {
                reader = easyocr.Reader(langs, gpu=False);
            } except Exception as reader_err {
                return {
                    "ok": False,
                    "text": "",
                    "variant_index": -1,
                    "score": -1.0,
                    "block_count": 0,
                    "blocks": [],
                    "error": "EasyOCR model load failed: {}. If this is SSL verification, install certifi and set SSL_CERT_FILE to certifi.where().".format(str(reader_err))
                };
            }
            _ocr_reader_cache[lang_key] = reader;
        }

        image = None;
        if is_base64 {
            raw_bytes = base64.b64decode(image_input);
            np_buf = np.frombuffer(raw_bytes, dtype=np.uint8);
            image = cv2.imdecode(np_buf, cv2.IMREAD_COLOR);
        } else {
            if not os.path.exists(image_input) {
                return {
                    "ok": False,
                    "text": "",
                    "variant_index": -1,
                    "score": -1.0,
                    "block_count": 0,
                    "blocks": [],
                    "error": "Image path not found: " + image_input
                };
            }
            image = cv2.imread(image_input, cv2.IMREAD_COLOR);
        }

        if image is None {
            return {
                "ok": False,
                "text": "",
                "variant_index": -1,
                "score": -1.0,
                "block_count": 0,
                "blocks": [],
                "error": "Failed to decode image input"
            };
        }

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);
        h = gray.shape[0];
        w = gray.shape[1];
        if w < 1200 {
            scale = 1200.0 / max(w, 1);
            gray = cv2.resize(gray, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC);
        }

        denoised = cv2.bilateralFilter(gray, 9, 75, 75);
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8));
        contrast = clahe.apply(denoised);

        thresh = cv2.threshold(contrast, 0, 255, 8)[1];
        coords = np.column_stack(np.where(thresh < 255));
        deskewed = contrast;
        if len(coords) >= 50 {
            angle = cv2.minAreaRect(coords)[-1];
            if angle < -45 {
                angle = -(90 + angle);
            } else {
                angle = -angle;
            }
            dh = contrast.shape[0];
            dw = contrast.shape[1];
            center = (dw // 2, dh // 2);
            mat = cv2.getRotationMatrix2D(center, angle, 1.0);
            deskewed = cv2.warpAffine(
                contrast,
                mat,
                (dw, dh),
                flags=cv2.INTER_CUBIC,
                borderMode=cv2.BORDER_REPLICATE
            );
        }

        variants: list[object] = [];
        variants.append(deskewed);
        variants.append(cv2.threshold(deskewed, 0, 255, 8)[1]);
        variants.append(
            cv2.adaptiveThreshold(
                deskewed,
                255,
                cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                cv2.THRESH_BINARY,
                31,
                11
            )
        );

        kernel = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]]);
        sharpen = cv2.filter2D(deskewed, -1, kernel);
        variants.append(cv2.threshold(sharpen, 0, 255, 8)[1]);

        best_text = "";
        best_blocks: list = [];
        best_block_count = 0;
        best_score = -1.0;
        best_index = -1;

        idx = 0;
        for variant in variants {
            blocks = reader.readtext(variant, detail=1, paragraph=False);
            if len(blocks) == 0 {
                continue;
            }

            conf_sum = 0.0;
            line_count = 0;
            text_accum = "";
            for block in blocks {
                text = str(block[1]).strip();
                conf = float(block[2]);
                if text {
                    if text_accum == "" {
                        text_accum = text;
                    } else {
                        text_accum = "{}\n{}".format(text_accum, text);
                    }
                    line_count += 1;
                    conf_sum += conf;
                }
            }

            score = conf_sum + (0.05 * line_count);
            if score > best_score {
                best_score = score;
                best_index = idx;
                best_text = text_accum;
                best_blocks = blocks;
                best_block_count = line_count;
            }
            idx += 1;
        }

        if best_index < 0 {
            return {
                "ok": False,
                "text": "",
                "variant_index": -1,
                "score": -1.0,
                "block_count": 0,
                "blocks": [],
                "error": "No text detected in image."
            };
        }

        return {
            "ok": True,
            "text": best_text,
            "variant_index": best_index,
            "score": best_score,
            "block_count": best_block_count,
            "blocks": best_blocks,
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

# Walker wrapper so frontend can call OCR through jac cloud endpoints.
walker:pub ExtractReceiptText {
    has image_input: str;
    has is_base64: bool = False;
    has languages: list[str] = [];

    can run with Root entry {
        report extract_receipt_text(self.image_input, self.is_base64, self.languages);
    }
}
