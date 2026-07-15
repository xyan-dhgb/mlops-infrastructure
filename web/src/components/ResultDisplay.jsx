import './ResultDisplay.css'

export default function ResultDisplay({ result, loading, error }) {
  if (error) {
    return (
      <div className="result-panel result-panel--error" id="result-error">
        <div className="result-panel__icon">⚠️</div>
        <p className="body-strong">Lỗi kết nối</p>
        <p className="caption">{error}</p>
      </div>
    )
  }

  if (loading) {
    return (
      <div className="result-panel result-panel--loading" id="result-loading">
        <div className="spinner" />
        <p className="body-strong">Đang phân tích...</p>
        <p className="caption">Mô hình đang xử lý ảnh và dữ liệu lâm sàng</p>
      </div>
    )
  }

  if (!result) {
    return (
      <div className="result-panel result-panel--empty" id="result-empty">
        <div className="result-panel__icon">🔬</div>
        <p className="body-strong">Chưa có kết quả</p>
        <p className="caption">Tải ảnh lên và nhấn "Dự đoán" để bắt đầu phân tích</p>
      </div>
    )
  }

  const isMalignant = result.label === 'Malignant'
  const prob = result.probability
  const percent = Math.round(prob * 100)

  return (
    <div
      className={`result-panel result-panel--done ${isMalignant ? 'result-panel--malignant' : 'result-panel--benign'}`}
      id="result-display"
    >
      {/* Label badge */}
      <div className={`result-badge ${isMalignant ? 'result-badge--malignant' : 'result-badge--benign'}`}>
        {isMalignant ? 'Ác tính' : 'Lành tính'}
      </div>

      {/* XAI Image Box */}
      {result.gradcam_base64 && (
        <div className="xai-container" style={{ marginTop: '1rem', textAlign: 'center' }}>
          <p className="caption" style={{ marginBottom: '0.5rem', fontWeight: 500 }}>
            Khoanh vùng giải thích XAI (Grad-CAM)
          </p>
          <img 
            src={`data:image/png;base64,${result.gradcam_base64}`} 
            alt="XAI Explanation"
            style={{ 
              maxWidth: '100%', 
              borderRadius: '8px', 
              boxShadow: '0 4px 12px rgba(0,0,0,0.1)' 
            }}
          />
        </div>
      )}

    </div>
  )
}
