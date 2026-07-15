import { useState } from 'react'
import './TabularForm.css'

const BASIC_FIELDS = [
  { key: 'age_approx', label: 'Tuổi xấp xỉ', type: 'number', min: 5, max: 100, step: 5 },
  {
    key: 'sex', label: 'Giới tính', type: 'select',
    options: [
      { value: '', label: 'Chọn giới tính' },
      { value: 'male', label: 'Nam' },
      { value: 'female', label: 'Nữ' },
    ],
  },
  {
    key: 'anatom_site_general', label: 'Vị trí giải phẫu', type: 'select',
    options: [
      { value: '', label: 'Chọn vị trí' },
      { value: 'head/neck', label: 'Đầu / Cổ' },
      { value: 'upper extremity', label: 'Chi trên' },
      { value: 'lower extremity', label: 'Chi dưới' },
      { value: 'anterior torso', label: 'Thân trước' },
      { value: 'posterior torso', label: 'Thân sau' },
      { value: 'palms/soles', label: 'Lòng bàn tay / chân' },
      { value: 'oral/genital', label: 'Miệng / Sinh dục' },
    ],
  },
  { key: 'clin_size_long_diam_mm', label: 'Đường kính dài nhất (mm)', type: 'number', min: 0.1, max: 50, step: 0.1 },
  { key: 'tbp_lv_dnn_lesion_confidence', label: 'DNN Lesion Confidence (0–100)', type: 'number', min: 0, max: 100, step: 0.1 },
]

const TBP_FIELDS = [
  { key: 'tbp_lv_a', label: 'A* trong tổn thương' },
  { key: 'tbp_lv_aext', label: 'A* ngoài tổn thương' },
  { key: 'tbp_lv_b', label: 'B* trong tổn thương' },
  { key: 'tbp_lv_bext', label: 'B* ngoài tổn thương' },
  { key: 'tbp_lv_c', label: 'Chroma trong tổn thương' },
  { key: 'tbp_lv_cext', label: 'Chroma ngoài tổn thương' },
  { key: 'tbp_lv_h', label: 'Hue trong tổn thương' },
  { key: 'tbp_lv_hext', label: 'Hue ngoài tổn thương' },
  { key: 'tbp_lv_l', label: 'L* trong tổn thương' },
  { key: 'tbp_lv_lext', label: 'L* ngoài tổn thương' },
  { key: 'tbp_lv_areamm2', label: 'Diện tích (mm²)' },
  { key: 'tbp_lv_area_perim_ratio', label: 'Tỉ lệ chu vi / diện tích' },
  { key: 'tbp_lv_color_std_mean', label: 'Độ không đồng đều màu' },
  { key: 'tbp_lv_deltaa', label: 'Tương phản A*' },
  { key: 'tbp_lv_deltab', label: 'Tương phản B*' },
  { key: 'tbp_lv_deltal', label: 'Tương phản L*' },
  { key: 'tbp_lv_deltalb', label: 'Tương phản LB' },
  { key: 'tbp_lv_deltalbnorm', label: 'Tương phản LB chuẩn hóa' },
  { key: 'tbp_lv_eccentricity', label: 'Độ lệch tâm' },
  { key: 'tbp_lv_minoraxismm', label: 'Đường kính ngắn nhất (mm)' },
  { key: 'tbp_lv_nevi_confidence', label: 'Nevus Confidence (0–100)' },
  { key: 'tbp_lv_norm_border', label: 'Chỉ số bất thường đường viền (0–10)' },
  { key: 'tbp_lv_norm_color', label: 'Chỉ số biến thiên màu (0–10)' },
  { key: 'tbp_lv_perimetermm', label: 'Chu vi (mm)' },
  { key: 'tbp_lv_radial_color_std_max', label: 'Bất đối xứng màu hướng tâm (0–10)' },
  { key: 'tbp_lv_stdl', label: 'Độ lệch chuẩn L* trong' },
  { key: 'tbp_lv_stdlext', label: 'Độ lệch chuẩn L* ngoài' },
  { key: 'tbp_lv_symm_2axis', label: 'Bất đối xứng viền (0–10)' },
  { key: 'tbp_lv_symm_2axis_angle', label: 'Góc bất đối xứng (°)' },
  { key: 'tbp_lv_x', label: 'Tọa độ X (3D TBP)' },
  { key: 'tbp_lv_y', label: 'Tọa độ Y (3D TBP)' },
  { key: 'tbp_lv_z', label: 'Tọa độ Z (3D TBP)' },
]

export default function TabularForm({ onTabularChange }) {
  const [values, setValues] = useState({})
  const [expanded, setExpanded] = useState(false)

  const handleChange = (key, raw) => {
    const next = { ...values }
    if (raw === '' || raw === undefined) {
      delete next[key]
    } else {
      // Keep select fields as string, number fields as number
      const field = [...BASIC_FIELDS, ...TBP_FIELDS].find((f) => f.key === key)
      next[key] = field?.type === 'select' ? raw : parseFloat(raw)
    }
    setValues(next)
    onTabularChange(next)
  }

  const renderField = (field) => {
    if (field.type === 'select') {
      return (
        <div className="form-group" key={field.key}>
          <label className="form-label" htmlFor={`field-${field.key}`}>{field.label}</label>
          <select
            id={`field-${field.key}`}
            className="form-input form-select"
            value={values[field.key] || ''}
            onChange={(e) => handleChange(field.key, e.target.value)}
          >
            {field.options.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>
      )
    }

    return (
      <div className="form-group" key={field.key}>
        <label className="form-label" htmlFor={`field-${field.key}`}>{field.label}</label>
        <input
          id={`field-${field.key}`}
          className="form-input"
          type="number"
          min={field.min}
          max={field.max}
          step={field.step || 'any'}
          placeholder="Để trống = tự động"
          value={values[field.key] ?? ''}
          onChange={(e) => handleChange(field.key, e.target.value)}
        />
      </div>
    )
  }

  return (
    <div className="tabular-form">
      <div className="tabular-form__basic">
        <p className="caption-strong tabular-form__section-title">
          Thông tin lâm sàng cơ bản
        </p>
        <div className="tabular-form__grid">
          {BASIC_FIELDS.map(renderField)}
        </div>
      </div>

      <div className="tabular-form__advanced">
        <button
          className="accordion-toggle"
          onClick={() => setExpanded(!expanded)}
          id="btn-toggle-advanced"
          type="button"
        >
          <span>Đặc trưng TBP nâng cao ({TBP_FIELDS.length} trường)</span>
          <svg
            className={`accordion-chevron ${expanded ? 'accordion-chevron--open' : ''}`}
            width="16" height="16" viewBox="0 0 16 16"
          >
            <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
        {expanded && (
          <div className="tabular-form__grid tabular-form__grid--advanced">
            {TBP_FIELDS.map(renderField)}
          </div>
        )}
        {!expanded && (
          <p className="caption tabular-form__hint">
            Các trường để trống sẽ được tự động điền giá trị trung vị (median) từ tập huấn luyện.
          </p>
        )}
      </div>
    </div>
  )
}
