class Country {
  final String code;
  final String nameKo;

  const Country(this.code, this.nameKo);
}

// ISO 3166-1 alpha-2 코드로 저장 (자유 텍스트는 "USA"/"US"/"미국"처럼 값이 갈라져서 드롭다운으로 고정)
const List<Country> countries = [
  Country('KR', '대한민국'),
  Country('US', '미국'),
  Country('JP', '일본'),
  Country('CN', '중국'),
  Country('TW', '대만'),
  Country('HK', '홍콩'),
  Country('TH', '태국'),
  Country('VN', '베트남'),
  Country('PH', '필리핀'),
  Country('SG', '싱가포르'),
  Country('MY', '말레이시아'),
  Country('ID', '인도네시아'),
  Country('IN', '인도'),
  Country('GB', '영국'),
  Country('FR', '프랑스'),
  Country('DE', '독일'),
  Country('ES', '스페인'),
  Country('IT', '이탈리아'),
  Country('CA', '캐나다'),
  Country('AU', '호주'),
  Country('NZ', '뉴질랜드'),
  Country('BR', '브라질'),
  Country('MX', '멕시코'),
  Country('AE', '아랍에미리트'),
  Country('SA', '사우디아라비아'),
  Country('RU', '러시아'),
  Country('OTHER', '기타'),
];
