{
     Flame screensaver Copyright (C) 2002 Ronald Hordijk
     Apophysis Copyright (C) 2001-2004 Mark Townsend

     This program is free software; you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published by
     the Free Software Foundation; either version 2 of the License, or
     (at your option) any later version.

     This program is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
     GNU General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with this program; if not, write to the Free Software
     Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
}
unit RenderMM;

interface

uses
  Windows, Graphics,
   Render, Controlpoint;

type
  TOnProgress = procedure(prog: double) of object;

type
  TColorMapColor = Record
    Red  : Int64;
    Green: Int64;
    Blue : Int64;
//    Count: Integer;
  end;
  PColorMapColor = ^TColorMapColor;
  TColorMapArray = array[0..255] of TColorMapColor;

  TBucket = Record
    Red  : Int64;
    Green: Int64;
    Blue : Int64;
    Count: Int64;
  end;
  PBucket = ^TBucket;
  TBucketArray = array of TBucket;

type
  TRendererMM64 = class(TBaseRenderer)
  private
    bm: TBitmap;

    oversample: Integer;
    filter_width: Integer;
    filter: array of array of extended;

    image_Width: Int64;
    image_Height: Int64;
    BucketWidth: Integer;
    BucketHeight: Integer;
    BucketSize: Integer;
    gutter_width: Integer;

    sample_density: extended;

    Buckets: TBucketArray;
    ColorMap: TColorMapArray;

    bg: array[0..2] of extended;
    vib_gam_n: Integer;
    vibrancy: double;
    gamma: double;

    bounds: array[0..3] of extended;
    size: array[0..1] of extended;
    FRotationCenter: array[0..1] of extended;
    ppux, ppuy: extended;
    nrSlices: int64;
    Slice: int64;

    procedure CreateFilter;
    procedure NormalizeFilter;

    procedure InitValues;
    procedure InitBuffers;
    procedure InitBitmap(w: Integer = 0; h: Integer = 0);
    procedure ClearBuffers;
    procedure ClearBuckets;
    procedure CreateColorMap;
    procedure CreateCamera;

    procedure AddPointsToBuckets(const points: TPointsArray); overload;
    procedure AddPointsToBucketsAngle(const points: TPointsArray); overload;

    procedure SetPixels;
    procedure CreateBMFromBuckets(YOffset: Integer = 0);

  protected
    function GetSlice: integer; override;
    function GetNrSlices: integer; override;

  public
    constructor Create; override;
    destructor Destroy; override;

    function  GetImage: TBitmap; override;

    procedure Render; override;

  end;

implementation

uses
  Math, Sysutils;

{ TRendererMM64 }

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.ClearBuckets;
var
  i: integer;
begin
  for i := 0 to BucketSize - 1 do begin
    buckets[i].Red   := 0;
    buckets[i].Green := 0;
    buckets[i].Blue  := 0;
    buckets[i].Count := 0;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.ClearBuffers;
begin
  ClearBuckets;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.CreateCamera;
var
  scale: double;
  t0, t1: double;
  corner0, corner1: double;
  shift: Integer;
begin
  scale := power(2, fcp.zoom);
  sample_density := fcp.sample_density * scale * scale;
  ppux := fcp.pixels_per_unit * scale;
  ppuy := fcp.pixels_per_unit * scale;
  // todo field stuff
  shift := 0;
  t0 := gutter_width / (oversample * ppux);
  t1 := gutter_width / (oversample * ppuy);
  corner0 := fcp.center[0] - image_width / ppux / 2.0;
  corner1 := fcp.center[1] - image_height / ppuy / 2.0;
  bounds[0] := corner0 - t0;
  bounds[1] := corner1 - t1 + shift;
  bounds[2] := corner0 + image_width / ppux + t0;
  bounds[3] := corner1 + image_height / ppuy + t1; //+ shift;
  if abs(bounds[2] - bounds[0]) > 0.01 then
    size[0] := 1.0 / (bounds[2] - bounds[0])
  else
    size[0] := 1;
  if abs(bounds[3] - bounds[1]) > 0.01 then
    size[1] := 1.0 / (bounds[3] - bounds[1])
  else
    size[1] := 1;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.CreateColorMap;
var
  i: integer;
begin
  for i := 0 to 255 do begin
    ColorMap[i].Red   := (fcp.CMap[i][0] * fcp.white_level) div 256;
    ColorMap[i].Green := (fcp.CMap[i][1] * fcp.white_level) div 256;
    ColorMap[i].Blue  := (fcp.CMap[i][2] * fcp.white_level) div 256;
//    cmap[i][3] := fcp.white_level;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.CreateFilter;
var
  i, j: integer;
  fw: integer;
  adjust: double;
  ii, jj: double;
begin
  oversample := fcp.spatial_oversample;
  fw := Trunc(2.0 * FILTER_CUTOFF * oversample * fcp.spatial_filter_radius);
  filter_width := fw + 1;

  // make sure it has same parity as oversample
  if odd(filter_width + oversample) then
    inc(filter_width);

  if (fw > 0.0) then
  	adjust := (1.0 * FILTER_CUTOFF * filter_width) / fw
  else
  	adjust := 1.0;

  setLength(filter, filter_width, filter_width);
  for i := 0 to filter_width - 1 do begin
    for j := 0 to filter_width - 1 do begin
      ii := ((2.0 * i + 1.0)/ filter_width - 1.0) * adjust;
      jj := ((2.0 * j + 1.0)/ filter_width - 1.0) * adjust;

      filter[i, j] :=  exp(-2.0 * (ii * ii + jj * jj));
    end;
  end;

  Normalizefilter;
end;

///////////////////////////////////////////////////////////////////////////////
destructor TRendererMM64.Destroy;
begin
  if assigned(bm) then
    bm.Free;

  inherited;
end;

///////////////////////////////////////////////////////////////////////////////
function TRendererMM64.GetImage: TBitmap;
begin
  Result := bm;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.InitBuffers;
begin
  gutter_width := (filter_width - oversample) div 2;
  BucketHeight := oversample * image_height + 2 * gutter_width;
  Bucketwidth := oversample * image_width + 2 * gutter_width;
  BucketSize := BucketWidth * BucketHeight;

  if high(buckets) <> (BucketSize - 1) then begin
    SetLength(buckets, BucketSize);
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.InitValues;
begin
  image_height := fcp.Height;
  image_Width := fcp.Width;

  CreateFilter;
  CreateCamera;

  InitBuffers;

  CreateColorMap;

  vibrancy := 0;
  gamma := 0;
  vib_gam_n := 0;
  bg[0] := 0;
  bg[1] := 0;
  bg[2] := 0;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.NormalizeFilter;
var
  i, j: integer;
  t: double;
begin
  t := 0;
  for i := 0 to filter_width - 1 do
    for j := 0 to filter_width - 1 do
      t := t + filter[i, j];

  for i := 0 to filter_width - 1 do
    for j := 0 to filter_width - 1 do
      filter[i, j] := filter[i, j] / t;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.AddPointsToBuckets(const points: TPointsArray);
var
  i: integer;
  px, py: double;
  bws, bhs: double;
  bx, by: double;
  wx, wy: double;
//  R: double;
//  V1, v2, v3: integer;
  Bucket: PBucket;
  MapColor: PColorMapColor;
begin
  bws := (BucketWidth - 0.5)  * size[0];
  bhs := (BucketHeight - 0.5) * size[1];
  bx := bounds[0];
  by := bounds[1];
  wx := bounds[2] - bounds[0];
  wy := bounds[3] - bounds[1];

  for i := SUB_BATCH_SIZE - 1 downto 0 do begin
    if FStop then
      Exit;

    px := points[i].x - bx;
    py := points[i].y - by;

    if ((px < 0) or (px > wx) or
        (py < 0) or (py > wy)) then
      continue;

    MapColor := @ColorMap[Round(points[i].c * 255)];
    Bucket := @buckets[Round(bws * px) + Round(bhs * py) * BucketWidth];

    Inc(Bucket.Red,   MapColor.Red);
    Inc(Bucket.Green, MapColor.Green);
    Inc(Bucket.Blue,  MapColor.Blue);
    Inc(Bucket.Count);
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.AddPointsToBucketsAngle(const points: TPointsArray);
var
  i: integer;
  px, py: double;
  ca,sa: double;
  nx, ny: double;
  bws, bhs: double;
  bx, by: double;
  wx, wy: double;
//  R: double;
//  V1, v2, v3: integer;
  Bucket: PBucket;
  MapColor: PColorMapColor;
begin

  bws := (BucketWidth - 0.5)  * size[0];
  bhs := (BucketHeight - 0.5) * size[1];
  bx := bounds[0];
  by := bounds[1];
  wx := bounds[2] - bounds[0];
  wy := bounds[3] - bounds[1];

  ca := cos(FCP.FAngle);
  sa := sin(FCP.FAngle);

  for i := SUB_BATCH_SIZE - 1 downto 0 do begin
    if FStop then
      Exit;

    px := points[i].x - FRotationCenter[0];
    py := points[i].y - FRotationCenter[1];

    nx := px * ca + py * sa;
    ny := -px * sa + py * ca;

    px := nx + FRotationCenter[0] - bx;
    py := ny + FRotationCenter[1] - by;

    if ((px < 0) or (px > wx) or
        (py < 0) or (py > wy)) then
      continue;

    MapColor := @ColorMap[Round(points[i].c * 255)];
    Bucket := @buckets[Round(bws * px) + Round(bhs * py) * BucketWidth];

    Inc(Bucket.Red,   MapColor.Red);
    Inc(Bucket.Green, MapColor.Green);
    Inc(Bucket.Blue,  MapColor.Blue);
    Inc(Bucket.Count);
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.SetPixels;
var
  i: integer;
  nsamples: Int64;
  nrbatches: Integer;
  points: TPointsArray;
begin
  SetLength(Points, SUB_BATCH_SIZE);

  nsamples := Round(sample_density * bucketSize / (oversample * oversample));
  nrbatches := Round(nsamples / (fcp.nbatches * SUB_BATCH_SIZE));
  Randomize;

  for i := 0 to nrbatches do begin
    if FStop then
      Exit;

    if (i and $F = 0) then
      if nrbatches > 0 then
        Progress(i / nrbatches)
      else
        Progress(0);

    // generate points
    case Compatibility of
      0: fcp.iterate_Old(SUB_BATCH_SIZE, points);
      1: fcp.iterateXYC(SUB_BATCH_SIZE, points);
    end;

    if FCP.FAngle = 0 then
      AddPointsToBuckets(points)
    else
      AddPointsToBucketsAngle(points);
  end;

  Progress(1);
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.CreateBMFromBuckets(YOffset: Integer);
var
  i, j: integer;
  alpha: double;
//  r,g,b: double;
  ai, ri, gi, bi: Integer;
  bgtot: Integer;
  ls: double;
  ii, jj: integer;
  fp: array[0..3] of double;
  Row: PLongintArray;
  vib, notvib: Integer;
  bgi: array[0..2] of Integer;
  bucketpos: Integer;
  filterValue: double;
  filterpos: Integer;
  lsa: array[0..1024] of double;
var
  k1, k2: double;
  area: double;
begin
  if fcp.gamma = 0 then
    gamma := fcp.gamma
  else
    gamma := 1 / fcp.gamma;
  vib := round(fcp.vibrancy * 256.0);
  notvib := 256 - vib;

  bgi[0] := round(fcp.background[0]);
  bgi[1] := round(fcp.background[1]);
  bgi[2] := round(fcp.background[2]);
  bgtot := RGB(bgi[2], bgi[1], bgi[0]);

  k1 := (fcp.Contrast * BRIGHT_ADJUST * fcp.brightness * 268 * PREFILTER_WHITE) / 256.0;
  area := image_width * image_height / (ppux * ppuy);
  k2 := (oversample * oversample) / (fcp.Contrast * area * fcp.White_level * sample_density);

  lsa[0] := 0;
  for i := 1 to 1024 do begin
    lsa[i] := (k1 * log10(1 + fcp.White_level * i * k2)) / (fcp.White_level * i);
  end;

  if filter_width > 1 then begin
    for i := 0 to BucketWidth * BucketHeight - 1 do begin
      if Buckets[i].count = 0 then
        Continue;

      ls := lsa[Min(1023, Buckets[i].Count)];

      Buckets[i].Red   := Round(Buckets[i].Red * ls);
      Buckets[i].Green := Round(Buckets[i].Green * ls);
      Buckets[i].Blue  := Round(Buckets[i].Blue * ls);
      Buckets[i].Count := Round(Buckets[i].Count * ls);
    end;
  end;

  ls := 0;
  ai := 0;
  bucketpos := 0;
  for i := 0 to Image_Height - 1 do begin
    if FStop then
      Break;

    Progress(i / Image_Height);

    Row := PLongintArray(bm.scanline[YOffset + i]);
    for j := 0 to Image_Width - 1 do begin
      if filter_width > 1 then begin
        fp[0] := 0;
        fp[1] := 0;
        fp[2] := 0;
        fp[3] := 0;

        for ii := 0 to filter_width - 1 do begin
          for jj := 0 to filter_width - 1 do begin
            filterValue := filter[ii, jj];
            filterpos := bucketpos + ii * BucketWidth + jj;

            fp[0] := fp[0] + filterValue * Buckets[filterpos].Red;
            fp[1] := fp[1] + filterValue * Buckets[filterpos].Green;
            fp[2] := fp[2] + filterValue * Buckets[filterpos].Blue;
            fp[3] := fp[3] + filterValue * Buckets[filterpos].Count;
          end;
        end;

        fp[0] := fp[0] / PREFILTER_WHITE;
        fp[1] := fp[1] / PREFILTER_WHITE;
        fp[2] := fp[2] / PREFILTER_WHITE;
        fp[3] := fcp.white_level * fp[3] / PREFILTER_WHITE;
      end else begin
        ls := lsa[Min(1023, Buckets[bucketpos].count)] / PREFILTER_WHITE;

        fp[0] := ls * Buckets[bucketpos].Red;
        fp[1] := ls * Buckets[bucketpos].Green;
        fp[2] := ls * Buckets[bucketpos].Blue;
        fp[3] := ls * Buckets[bucketpos].Count * fcp.white_level;
      end;

      Inc(bucketpos, oversample);

      if (fp[3] > 0.0) then begin
        alpha := power(fp[3], gamma);
        ls := vib * alpha / fp[3];
        ai := round(alpha * 256);
        if (ai < 0) then
          ai := 0
        else if (ai > 256) then
          ai := 256;
        ai := 256 - ai;
      end else begin
        // no intensity so simply set the BG;
        Row[j] := bgtot;
        continue;
      end;

      if (notvib > 0) then
        ri := Round(ls * fp[0] + notvib * power(fp[0], gamma))
      else
        ri := Round(ls * fp[0]);
      ri := ri + (ai * bgi[0]) shr 8;
      if (ri < 0) then
        ri := 0
      else if (ri > 255) then
        ri := 255;

      if (notvib > 0) then
        gi := Round(ls * fp[1] + notvib * power(fp[1], gamma))
      else
        gi := Round(ls * fp[1]);
      gi := gi + (ai * bgi[1]) shr 8;
      if (gi < 0) then
        gi := 0
      else if (gi > 255) then
        gi := 255;

      if (notvib > 0) then
        bi := Round(ls * fp[2] + notvib * power(fp[2], gamma))
      else
        bi := Round(ls * fp[2]);
      bi := bi + (ai * bgi[2]) shr 8;
      if (bi < 0) then
        bi := 0
      else if (bi > 255) then
        bi := 255;

      Row[j] := RGB(bi, gi, ri);
    end;

    Inc(bucketpos, 2 * gutter_width);
    Inc(bucketpos, (oversample - 1) * BucketWidth);
  end;

  Progress(1);
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.InitBitmap(w, h: Integer);
begin
  if not Assigned(bm) then
    bm := TBitmap.Create;

  bm.PixelFormat := pf32bit;

  if (w <> 0) and (h <> 0) then begin
    bm.Width := w;
    bm.Height := h;
  end else begin
    bm.Width := image_Width;
    bm.Height := image_Height;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
constructor TRendererMM64.Create;
begin
  inherited Create;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRendererMM64.Render;
const
  Dividers: array[0..15] of integer = (1, 2, 3, 4, 5, 6, 7, 8, 10, 16, 20, 32, 64, 128, 256, 512);
var
  ApproxMemory, MaxMemory: int64;
  i: integer;
  zoom_scale, center_base, center_y: double;
begin
  FStop := False;

  FRotationCenter[0] := fcp.center[0];
  FRotationCenter[1] := fcp.center[1];

  image_height := fcp.Height;
  image_Width := fcp.Width;
  oversample := fcp.spatial_oversample;

  // entered memory - imagesize
  MaxMemory := FMaxMem * 1024 * 1024 - 4 * image_height * image_width;

  ApproxMemory := 32 * oversample * oversample * image_height * image_width;

  if (MaxMemory < 0) then
    Exit;

  nrSlices := 1 + ApproxMemory div MaxMemory;

  if nrSlices > Dividers[High(Dividers)] then begin
    for i := High(Dividers) downto 0 do begin
      if image_height <> (image_height div dividers[i]) * dividers[i] then begin
        nrSlices := dividers[i];
        break;
      end;
    end;
  end else begin
    for i := 0 to High(Dividers) do begin
      if image_height <> (image_height div dividers[i]) * dividers[i] then
        continue;
      if nrslices <= dividers[i] then begin
        nrSlices := dividers[i];
        break;
      end;
    end;
  end;

  fcp.sample_density := fcp.sample_density * nrslices;
  fcp.height := fcp.height div nrslices;
  center_y := fcp.center[1];
  zoom_scale := power(2.0, fcp.zoom);
  center_base := center_y - ((nrslices - 1) * fcp.height) /  (2 * fcp.pixels_per_unit * zoom_scale);

  InitValues;
  InitBitmap(fcp.Width, NrSlices * fcp.Height);

  for i := 0 to NrSlices - 1 do begin
    Slice := i;
    fcp.center[1] := center_base + fcp.height * slice / (fcp.pixels_per_unit * zoom_scale);
    CreateCamera;
    ClearBuffers;
    SetPixels;
    CreateBMFromBuckets(Slice * fcp.height);
  end;
  bm.PixelFormat := pf24bit;

  fcp.sample_density := fcp.sample_density / nrslices;
  fcp.height := fcp.height * nrslices;
end;

///////////////////////////////////////////////////////////////////////////////
function TRendererMM64.GetSlice: integer;
begin
  Result := Slice;
end;

///////////////////////////////////////////////////////////////////////////////
function TRendererMM64.GetNrSlices: integer;
begin
  Result := NrSlices;
end;

///////////////////////////////////////////////////////////////////////////////
end.

