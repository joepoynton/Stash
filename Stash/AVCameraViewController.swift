//
//  AVCameraViewController.swift
//  Stash

import UIKit
import AVFoundation

class AVCameraViewController: UIViewController {

    var onPhotoCaptured: ((Data) -> Void)?

    // MARK: - AV objects

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let photoOutput = AVCapturePhotoOutput()
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var captureDevice: AVCaptureDevice?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreviewLayer()
        setupControlButtons()
        checkPermissionsAndSetupSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard session.isRunning, let rc = rotationCoordinator else { return }
        let angle = rc.videoRotationAngleForHorizonLevelPreview
        previewLayer.connection?.videoRotationAngle = angle
        photoOutput.connection(with: .video)?.videoRotationAngle = angle
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self, let rc = self.rotationCoordinator else { return }
            self.previewLayer.frame = self.view.bounds
            self.previewLayer.connection?.videoRotationAngle = rc.videoRotationAngleForHorizonLevelPreview
        }
    }

    // MARK: - UI setup

    private func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }

    private func setupControlButtons() {
        // Shutter button
        let shutterButton = UIButton(type: .system)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        let shutterConfig = UIImage.SymbolConfiguration(pointSize: 72, weight: .thin)
        shutterButton.setImage(UIImage(systemName: "circle.fill", withConfiguration: shutterConfig), for: .normal)
        shutterButton.tintColor = .white
        shutterButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)

        // Close button
        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeConfig), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(dismissCamera), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])
    }

    // MARK: - Session setup

    private func checkPermissionsAndSetupSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupSession() } else { self?.showPermissionDenied() }
                }
            }
        default:
            showPermissionDenied()
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        captureDevice = device

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        // RotationCoordinator needs both the device and the already-configured preview layer.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        // Store the token as an instance property so it is never deallocated.
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.previewLayer.connection?.videoRotationAngle = angle
                self.photoOutput.connection(with: .video)?.videoRotationAngle = angle
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            // Apply initial rotation after the session is running so the preview
            // layer connection is active and the angle sticks on first appearance.
            DispatchQueue.main.async {
                guard let self, let rc = self.rotationCoordinator else { return }
                let angle = rc.videoRotationAngleForHorizonLevelPreview
                self.previewLayer.connection?.videoRotationAngle = angle
                self.photoOutput.connection(with: .video)?.videoRotationAngle = angle
            }
        }
    }

    private func showPermissionDenied() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Camera access is required.\nPlease enable it in Settings."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
    }

    // MARK: - Actions

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        // Apply horizon-level rotation to the capture connection before shooting.
        if let rc = rotationCoordinator,
           let connection = photoOutput.connection(with: .video) {
            connection.videoRotationAngle = rc.videoRotationAngleForHorizonLevelCapture
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func dismissCamera() {
        dismiss(animated: true)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension AVCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onPhotoCaptured?(data)
            self?.dismiss(animated: true)
        }
    }
}
