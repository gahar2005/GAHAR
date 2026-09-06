import 'package:flutter/material.dart';
import '../models/platform_models.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class ExpertsHubScreen extends StatefulWidget {
  const ExpertsHubScreen({super.key});

  @override
  State<ExpertsHubScreen> createState() => _ExpertsHubScreenState();
}

class _ExpertsHubScreenState extends State<ExpertsHubScreen> {
  final List<ExpertProfile> _experts = [
    ExpertProfile(
      id: 'exp_01',
      name: 'Dr. Tarek El-Morsy',
      title: 'Senior GAHAR Surveyor & Quality Consultant',
      specialty: 'Hospital Governance & Patient Safety (GSR & PCC)',
      gaharCertNumber: 'GAHAR-EXP-2023-019',
      yearsExperience: 14,
      rating: 4.9,
      reviewsCount: 28,
      avatarUrl: '',
    ),
    ExpertProfile(
      id: 'exp_02',
      name: 'Dr. Mona Abdel-Rahman',
      title: 'Infection Control & Sterilization Specialist',
      specialty: 'Infection Prevention & Control (IPC)',
      gaharCertNumber: 'GAHAR-EXP-2022-045',
      yearsExperience: 11,
      rating: 4.8,
      reviewsCount: 19,
      avatarUrl: '',
    ),
    ExpertProfile(
      id: 'exp_03',
      name: 'Eng. Ahmed Al-Ghazali',
      title: 'Facility Safety & Engineering Consultant',
      specialty: 'Facility & Safety Management (FMS)',
      gaharCertNumber: 'GAHAR-EXP-2024-008',
      yearsExperience: 16,
      rating: 5.0,
      reviewsCount: 34,
      avatarUrl: '',
    ),
  ];

  void _requestConsultation(ExpertProfile expert) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Request Consultation: ${expert.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Specialty: ${expert.specialty}\nGAHAR Cert: ${expert.gaharCertNumber}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Topic / Consultation Request Details',
                  hintText: 'e.g. Mock Audit review for Infection Control',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Consultation request submitted to ${expert.name}. They will contact you shortly.'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
              child: const Text('Submit Request'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Experts Hub',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accreditation Experts Hub / خبراء الاعتماد'),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _experts.length,
          itemBuilder: (context, index) {
            final expert = _experts[index];

            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.primary.withOpacity(0.15),
                          child: Icon(Icons.person, color: AppColors.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                expert.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                expert.title,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.star,
                                      size: 14, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${expert.rating} (${expert.reviewsCount} reviews)',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${expert.yearsExperience} yrs exp',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Specialty: ${expert.specialty}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Book Advisory Session / طلب استشارة'),
                        onPressed: () => _requestConsultation(expert),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
