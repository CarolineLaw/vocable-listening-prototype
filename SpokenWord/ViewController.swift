/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The root view controller that provides a button to start and stop recording, and which displays the speech recognition results.
*/

import UIKit
import Speech

public class ViewController: UIViewController, SFSpeechRecognizerDelegate {
    // MARK: Properties
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let audioEngine = AVAudioEngine()

    private var response = String()

    private let yesNoResponses = ["yes", "no"]
    private let quantityResponses = ["1","2","3","4","5","6","7","8","9","0"]
    private let feelingsResponses = ["okay", "good", "bad"]
    let prefixes = ["Would you like", "Do you want"]
    var choices = [String]()

    @IBOutlet var textView: UITextView!
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var recordButton: UIButton!
    
    // MARK: View Controller Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable the record buttons until authorization has been granted.
        recordButton.isEnabled = false
        recordButton.layer.cornerRadius = 6

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(UINib(nibName: "ResponseCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: "ResponseCell")
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Configure the SFSpeechRecognizer object already
        // stored in a local member variable.
        speechRecognizer.delegate = self
        
        // Asynchronously make the authorization request.
        SFSpeechRecognizer.requestAuthorization { authStatus in

            // Divert to the app's main thread so that the UI
            // can be updated.
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.recordButton.isEnabled = true
                    
                case .denied:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("User denied access to speech recognition", for: .disabled)
                    
                case .restricted:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("Speech recognition restricted on this device", for: .disabled)
                    
                case .notDetermined:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("Speech recognition not yet authorized", for: .disabled)
                    
                default:
                    self.recordButton.isEnabled = false
                }
            }
        }
    }
    
    private func startRecording() throws {
        
        // Cancel the previous task if it's running.
        recognitionTask?.cancel()
        self.recognitionTask = nil
        
        // Configure the audio session for the app.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode

        // Create and configure the speech recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object") }
        recognitionRequest.shouldReportPartialResults = true
        
        // Keep speech recognition data on device
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        // Create a recognition task for the speech recognition session.
        // Keep a reference to the task so that it can be canceled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            
            if let result = result {
                // Update the text view with the results.
                self.textView.text = result.bestTranscription.formattedString
                isFinal = result.isFinal

                let model = VocableChoicesModel()
                
                guard let response = try? model.prediction(text: result.bestTranscription.formattedString) else { return }

                if isFinal {
                    print("\(result.bestTranscription.formattedString)")

                    //get choices
                    var sentence = result.bestTranscription.formattedString

                    for prefix in self.prefixes {
                        if sentence.hasPrefix(prefix) {
                            if let rangeToRemove = sentence.range(of: prefix) {
                                sentence.removeSubrange(rangeToRemove)
                            }
                        }
                    }

                    sentence = sentence.trimmingCharacters(in: .whitespaces)
                    self.choices = sentence.components(separatedBy: "or")
                    self.choices = self.choices.map { (choice) -> String in
                        var sanitizedChoice = choice.trimmingCharacters(in: .whitespaces)
                        if sanitizedChoice.hasPrefix("a ") {
                            if let rangeToRemove = sanitizedChoice.range(of: "a ") {
                                sanitizedChoice.removeSubrange(rangeToRemove)
                            }
                        }
                        return sanitizedChoice
                    }

                    let label = response.label
                    self.response = label
                    self.collectionView.reloadData()
                    self.collectionView.isHidden = false
                    if label == "boolean" {
                        print("bool")
                    } else if label == "quantity" {
                        print("numbers")
                    } else if label == "feelings" {
                        print("feels")
                    } else if label == "choices" {
                        print("choice!")
                        print(self.choices)
                    }
                }
            }
            
            if error != nil || isFinal {
                // Stop recognizing speech if there is a problem.
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recordButton.isEnabled = true
                self.recordButton.setTitle("Start Recording", for: [])
            }
        }

        // Configure the microphone input.
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Let the user know to start talking.
        textView.text = "(Go ahead, I'm listening)"
    }
    
    // MARK: SFSpeechRecognizerDelegate
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle("Start Recording", for: [])
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle("Recognition Not Available", for: .disabled)
        }
    }
    
    // MARK: Interface Builder actions
    
    @IBAction func recordButtonTapped() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recordButton.isEnabled = false
            recordButton.setTitle("Stopping", for: .disabled)
        } else {
            do {
                try startRecording()
                recordButton.setTitle("Stop Recording", for: [])
            } catch {
                recordButton.setTitle("Recording Not Available", for: [])
            }
        }
    }
}

extension ViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if self.response == "boolean" {
            return 2
        } else if  self.response == "feelings" {
            return 3
        } else if self.response == "quantity" {
            return 10
        } else if self.response == "choices" {
            return choices.count
        } else {
            return 1
        }
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ResponseCell", for: indexPath) as! ResponseCollectionViewCell
        cell.textLabel.layer.cornerRadius = 6
        cell.textLabel.layer.masksToBounds = true
        if self.response == "boolean" {
            cell.textLabel.text = yesNoResponses[indexPath.row]
        } else if  self.response == "feelings" {
            cell.textLabel.text = feelingsResponses[indexPath.row]
        } else if self.response == "quantity" {
            cell.textLabel.text = quantityResponses[indexPath.row]
        } else if self.response == "choices" {
            // get words from sentance put them in the button
            cell.textLabel.text = choices[indexPath.row]
        }

        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 8.0
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if self.response == "boolean" || self.response == "feelings" || self.response == "choices" {
            return CGSize(width:UIScreen.main.bounds.width - 100, height: CGFloat(150))
        } else if self.response == "quantity" {
            let itemHeight = CGFloat(100)
            let sectionInset = (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset.left ?? 0
            let availableWidth = collectionView.bounds.width - sectionInset
            let calculatedItemWidth = availableWidth / 3
            return CGSize(width: calculatedItemWidth, height: itemHeight)
        } else {
            return CGSize(width:100, height: CGFloat(150))
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        var utterance = String()
            if self.response == "boolean" {
                utterance = self.yesNoResponses[indexPath.row]
            } else if self.response == "feelings" {
                utterance = self.feelingsResponses[indexPath.row]
            } else if self.response == "quantity" {
                utterance = self.quantityResponses[indexPath.row]
            }

        DispatchQueue.global(qos: .userInitiated).async {
            AVSpeechSynthesizer.shared.speak(utterance, language: "en")
        }
    }
}
