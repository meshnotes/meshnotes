class DocTitle {
  String docId;
  String title;
  int updateTime;
  String docHash = '';

  DocTitle({
    required this.docId,
    required this.title,
    this.updateTime=0,
  });
}