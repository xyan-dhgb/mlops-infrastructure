import { useState, useRef } from 'react'
import './ImageUpload.css'

export default function ImageUpload({ onImageSelect }) {
  const [preview, setPreview] = useState(null)
  const [fileName, setFileName] = useState('')
  const [isDragging, setIsDragging] = useState(false)
  const inputRef = useRef(null)

  const processFile = (file) => {
    if (!file || !file.type.startsWith('image/')) return
    setFileName(file.name)

    const reader = new FileReader()
    reader.onload = (e) => {
      const dataUrl = e.target.result
      setPreview(dataUrl)
      // Extract pure base64 (remove "data:image/...;base64,")
      const base64 = dataUrl.split(',')[1]
      onImageSelect(base64)
    }
    reader.readAsDataURL(file)
  }

  const handleDrop = (e) => {
    e.preventDefault()
    setIsDragging(false)
    const file = e.dataTransfer.files[0]
    processFile(file)
  }

  const handleDragOver = (e) => {
    e.preventDefault()
    setIsDragging(true)
  }

  const handleDragLeave = () => setIsDragging(false)

  const handleFileInput = (e) => {
    processFile(e.target.files[0])
  }

  const handleClear = () => {
    setPreview(null)
    setFileName('')
    onImageSelect(null)
    if (inputRef.current) inputRef.current.value = ''
  }

  return (
    <div className="image-upload-wrapper">
      {!preview ? (
        <div
          className={`dropzone ${isDragging ? 'dropzone--active' : ''}`}
          onDrop={handleDrop}
          onDragOver={handleDragOver}
          onDragLeave={handleDragLeave}
          onClick={() => inputRef.current?.click()}
          id="image-dropzone"
        >
          <div className="dropzone__icon">
            <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
              <rect x="4" y="8" width="40" height="32" rx="4" stroke="currentColor" strokeWidth="2"/>
              <circle cx="16" cy="20" r="4" stroke="currentColor" strokeWidth="2"/>
              <path d="M4 32l10-10 8 8 6-6 16 16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
          </div>
          <p className="dropzone__title">Kéo thả ảnh da liễu vào đây</p>
          <p className="dropzone__subtitle">hoặc nhấp để chọn file</p>
          <p className="dropzone__hint">PNG, JPG, JPEG • Tối đa 10MB</p>
          <input
            ref={inputRef}
            type="file"
            accept="image/png,image/jpeg,image/jpg"
            onChange={handleFileInput}
            style={{ display: 'none' }}
            id="image-file-input"
          />
        </div>
      ) : (
        <div className="preview-container">
          <div className="preview-image-wrap">
            <img src={preview} alt="Ảnh tổn thương da" className="preview-image" />
          </div>
          <div className="preview-info">
            <span className="preview-filename caption">{fileName}</span>
            <button
              className="btn-clear"
              onClick={handleClear}
              id="btn-clear-image"
            >
              Xóa ảnh
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
